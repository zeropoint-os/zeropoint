#!/usr/bin/env python3
"""
Zeropoint Boot Services Unit File Generator

Reads boot-services.yaml and generates systemd unit files for all boot phases.
Validates dependency ordering and phase transitions.
"""

import yaml
import sys
from pathlib import Path
from typing import Dict, List, Set


class BootServiceGenerator:
    TEMPLATE = """[Unit]
Description={description}
Documentation=https://docs.zeropoint.example.com/boot-phases
DefaultDependencies=no
{after}{conditions}
[Service]
Type=oneshot
ExecStart=/usr/local/bin/{script}
Environment=DEBIAN_FRONTEND=noninteractive
StandardOutput=journal+console
StandardError=journal+console
TimeoutSec={timeout}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
"""

    def __init__(self, yaml_file: str, output_dir: str = "files/etc/systemd/system"):
        self.yaml_file = Path(yaml_file)
        self.output_dir = Path(output_dir)
        self.pifile_output = Path("modules/services/boot-services.Pifile")
        self.config = self._load_yaml()
        self.phase_order = []
        self.services_by_phase = {}
        self.all_services = {}

    def _load_yaml(self) -> dict:
        """Load and parse the YAML configuration."""
        with open(self.yaml_file, 'r') as f:
            return yaml.safe_load(f)

    def _validate_config(self) -> bool:
        """Validate configuration for errors."""
        errors = []
        phases = self.config.get('phases', {})

        if not phases:
            errors.append("No phases defined in configuration")
            return False

        # Check phase ordering
        phase_order = self.config.get('phase_order', [])
        if not phase_order:
            errors.append("phase_order not defined")
            return False

        for phase in phase_order:
            if phase not in phases:
                errors.append(f"Phase '{phase}' in phase_order not defined in phases")

        # Check all services
        for phase_name, phase_data in phases.items():
            services = phase_data.get('services', [])
            for svc in services:
                if not svc.get('name'):
                    errors.append(f"Service in {phase_name} missing 'name'")
                if not svc.get('script'):
                    errors.append(f"Service {svc.get('name')} missing 'script'")
                if not svc.get('description'):
                    errors.append(f"Service {svc.get('name')} missing 'description'")

                # Validate dependencies
                after = svc.get('after', [])
                if after and not isinstance(after, list):
                    after = [after]

                for dep in after:
                    # Check if dependency exists
                    found = False
                    for p, pd in phases.items():
                        for s in pd.get('services', []):
                            if s.get('name') == dep or p == dep:
                                found = True
                                break
                    if not found:
                        errors.append(f"Service {svc.get('name')} depends on unknown '{dep}'")

        if errors:
            for err in errors:
                print(f"ERROR: {err}", file=sys.stderr)
            return False

        return True

    def _resolve_dependencies(self, service: dict, phase_name: str) -> tuple:
        """Resolve After and Before dependencies for a service."""
        after = []

        service_after = service.get('after', [])
        if not isinstance(service_after, list):
            service_after = [service_after]

        phases = self.config.get('phases', {})
        phase_order = self.config.get('phase_order', [])

        for dep in service_after:
            # If it's a service name, find it and add service dependency
            if dep in self.all_services:
                after.append(f"zeropoint-{dep}.service")
            # If it's a phase name, find the last service in that phase and depend on it
            elif dep in phases:
                phase_services = phases[dep].get('services', [])
                if phase_services:
                    # Depend on the last (latest) service in that phase
                    last_service = phase_services[-1]['name']
                    after.append(f"zeropoint-{last_service}.service")

        return after, []

    def generate(self) -> bool:
        """Generate all unit files and Pifile."""
        if not self._validate_config():
            return False

        phases = self.config.get('phases', {})
        self.phase_order = self.config.get('phase_order', [])

        # Build service registry for dependency resolution
        for phase_name, phase_data in phases.items():
            services = phase_data.get('services', [])
            self.services_by_phase[phase_name] = services
            for svc in services:
                self.all_services[svc['name']] = (phase_name, svc)

        # Generate systemd unit files
        self.output_dir.mkdir(parents=True, exist_ok=True)
        generated = []

        for phase_name in self.phase_order:
            phase_data = phases[phase_name]
            services = phase_data.get('services', [])

            for service in services:
                name = service['name']
                script = service['script']
                description = service['description']
                timeout = service.get('timeout', 300)

                # Resolve dependencies
                after_deps, _ = self._resolve_dependencies(service, phase_name)
                after_str = ""
                if after_deps:
                    after_str = "After=" + " ".join(after_deps) + "\n"

                # Handle conditions
                conditions_str = ""
                
                # Add default condition to skip if already completed
                conditions_str += f"ConditionPathExists=!/etc/zeropoint/.zeropoint-{name}\n"
                
                # Add any custom conditions from YAML
                if 'conditions' in service:
                    for condition in service['conditions']:
                        # Handle shorthand conditions like "service.marker" or "!service.marker"
                        if condition.startswith('!') and '.' in condition:
                            # Negated marker: !zeropoint-setup-nvidia-drivers.reboot-required
                            marker = condition[1:]  # Remove !
                            conditions_str += f"ConditionPathExists=!/etc/zeropoint/.{marker}\n"
                        elif '.' in condition and not condition.startswith('Condition'):
                            # Positive marker: zeropoint-setup-nvidia-drivers.reboot-required  
                            conditions_str += f"ConditionPathExists=/etc/zeropoint/.{condition}\n"
                        else:
                            # Raw systemd condition - pass through as-is
                            conditions_str += condition + "\n"

                # Generate unit file content
                unit_content = self.TEMPLATE.format(
                    description=description,
                    after=after_str,
                    conditions=conditions_str,
                    script=script,
                    timeout=timeout,
                )

                # Write unit file
                unit_file = self.output_dir / f"zeropoint-{name}.service"
                with open(unit_file, 'w') as f:
                    f.write(unit_content)

                generated.append(f"  {unit_file.relative_to(self.output_dir)}")

        print("Generated unit files:")
        for f in generated:
            print(f)

        # Generate Pifile with all INSTALL directives
        self._generate_pifile(phases)

        return True

    def _generate_pifile(self, phases: dict):
        """Generate Pifile with all service installation directives."""
        pifile_content = """# Auto-generated from boot-services.yaml
# Run: python3 generate-unit-files.py to regenerate

# Install zeropoint boot-time utility scripts
INSTALL 755 files/usr/local/bin/zeropoint-common.sh /usr/local/bin/zeropoint-common.sh
"""
        
        # Collect all unique scripts
        scripts_seen = set()
        for phase_name in self.phase_order:
            phase_data = phases[phase_name]
            services = phase_data.get('services', [])
            
            for service in services:
                script = service['script']
                if script not in scripts_seen:
                    pifile_content += f"INSTALL 755 files/usr/local/bin/{script} /usr/local/bin/{script}\n"
                    scripts_seen.add(script)
        
        # Add service unit installation section
        pifile_content += "\n# Install all zeropoint boot-time service unit files\n"
        
        for phase_name in self.phase_order:
            phase_data = phases[phase_name]
            services = phase_data.get('services', [])
            
            pifile_content += f"\n# {phase_data['description']}\n"
            
            for service in services:
                name = service['name']
                pifile_content += f"INSTALL files/etc/systemd/system/zeropoint-{name}.service /etc/systemd/system/zeropoint-{name}.service\n"
        
        # Add enable commands
        pifile_content += "\n# Enable all boot-time services\n"
        enable_list = []
        for phase_name in self.phase_order:
            phase_data = phases[phase_name]
            services = phase_data.get('services', [])
            for service in services:
                enable_list.append(f"zeropoint-{service['name']}.service")
        
        # Group into reasonable line lengths
        pifile_content += "RUN systemctl enable"
        for i, service in enumerate(enable_list):
            if i > 0 and i % 5 == 0:
                pifile_content += " \\\n    "
            pifile_content += f" {service}"
        pifile_content += "\n"
        
        # Write Pifile
        self.pifile_output.parent.mkdir(parents=True, exist_ok=True)
        with open(self.pifile_output, 'w') as f:
            f.write(pifile_content)
        
        print(f"\nGenerated Pifile: {self.pifile_output}")

    def show_execution_plan(self):
        """Display the boot execution plan."""
        print("\n📋 Boot Execution Plan:\n")

        phases = self.config.get('phases', {})
        phase_order = self.config.get('phase_order', [])

        for i, phase_name in enumerate(phase_order, 1):
            phase_data = phases[phase_name]
            services = phase_data.get('services', [])

            print(f"{i}. {phase_name.upper()}")
            for svc in services:
                after = svc.get('after', [])
                after_str = f" [after: {', '.join(after)}]" if after else ""
                print(f"   - {svc['name']}{after_str}")
            print()


def main():
    if len(sys.argv) > 1:
        yaml_file = sys.argv[1]
    else:
        yaml_file = "boot-services.yaml"

    if len(sys.argv) > 2:
        output_dir = sys.argv[2]
    else:
        output_dir = "files/etc/systemd/system"

    try:
        gen = BootServiceGenerator(yaml_file, output_dir)
        gen.show_execution_plan()

        if gen.generate():
            print("\n✓ Unit files generated successfully")
            return 0
        else:
            print("\n✗ Generation failed", file=sys.stderr)
            return 1
    except FileNotFoundError:
        print(f"ERROR: {yaml_file} not found", file=sys.stderr)
        return 1
    except yaml.YAMLError as e:
        print(f"ERROR: Failed to parse YAML: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
