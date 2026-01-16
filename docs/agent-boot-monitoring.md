# Zeropoint Agent Boot Monitoring

The Zeropoint Agent provides real-time monitoring and status visualization of the boot process while system installation and configuration services are running.

## Overview

The agent starts early in the boot process and can monitor ongoing boot services through structured syslog parsing, providing users with:

- Real-time progress visualization
- Service status dashboard
- Live log streaming
- Phase completion tracking

## Architecture

### Service Logging Framework

All boot services use the `zeropoint-common.sh` framework which provides structured logging:

```bash
# Each service logs with consistent tags
logger -t zeropoint-hostname "=== Generating Memorable Hostname ==="
logger -t zeropoint-storage "Selected largest disk: /dev/sdb (500GB)"

# Progress markers are logged with checkmarks
mark "gpu-detected"          # → "✓ gpu-detected"
mark "driver-installed"      # → "✓ driver-installed"
```

### Agent Monitoring Integration

The agent monitors `/var/log/journal` and `/dev/log` for real-time syslog entries.

#### 1. Journal Reader Implementation

```go
// Monitor systemd journal for boot service events
func (m *BootMonitor) StreamJournal() {
    journal, err := sdjournal.NewJournal()
    if err != nil {
        log.Printf("Failed to open journal: %v", err)
        return
    }
    
    // Filter for zeropoint services
    journal.AddMatch("_SYSTEMD_UNIT=zeropoint-*.service")
    journal.SeekTail()
    
    for {
        n, err := journal.Next()
        if err != nil || n == 0 {
            journal.Wait(time.Second)
            continue
        }
        
        entry := m.parseJournalEntry(journal)
        m.updateServiceStatus(entry)
    }
}
```

#### 2. Log Entry Parsing

```go
type ServiceEntry struct {
    Service   string    `json:"service"`
    Phase     string    `json:"phase"`
    Message   string    `json:"message"`
    Level     string    `json:"level"`
    Timestamp time.Time `json:"timestamp"`
    IsMarker  bool      `json:"is_marker"`
    Step      string    `json:"step,omitempty"`
}

func (m *BootMonitor) parseJournalEntry(journal *sdjournal.Journal) ServiceEntry {
    message, _ := journal.GetData("MESSAGE")
    unit, _ := journal.GetData("_SYSTEMD_UNIT")
    
    // Extract service name from unit (zeropoint-hostname.service → hostname)
    service := strings.TrimSuffix(strings.TrimPrefix(unit, "zeropoint-"), ".service")
    
    // Parse marker messages: "✓ driver-installed" 
    if strings.HasPrefix(message, "✓ ") {
        return ServiceEntry{
            Service:  service,
            Message:  message,
            IsMarker: true,
            Step:     strings.TrimPrefix(message, "✓ "),
        }
    }
    
    return ServiceEntry{
        Service: service,
        Message: message,
        IsMarker: false,
    }
}
```

### Real-Time Status Dashboard

#### Web Interface Components

**1. Phase Overview**
```html
<div class="boot-phases">
  <div class="phase completed">
    <h3>🟢 Base System</h3>
    <div class="services">
      <span class="service completed">✓ set-memorable-hostname</span>
      <span class="service completed">✓ resize-rootfs</span>
    </div>
  </div>
  
  <div class="phase running">
    <h3>🔄 Storage Setup</h3>
    <div class="services">
      <span class="service completed">✓ setup-storage</span>
      <span class="service running">⏳ configure-apt-storage</span>
    </div>
  </div>
  
  <div class="phase pending">
    <h3>⏸️ Drivers</h3>
    <div class="services">
      <span class="service pending">⏳ setup-nvidia-drivers</span>
      <span class="service pending">⏳ setup-nvidia-post-reboot</span>
    </div>
  </div>
</div>
```

**2. Live Log Stream**
```html
<div class="log-stream">
  <div class="log-entry">
    <span class="timestamp">02:37:33</span>
    <span class="service">nvidia-drivers</span>
    <span class="message">Installing recommended driver: nvidia-driver-535</span>
  </div>
  
  <div class="log-entry marker">
    <span class="timestamp">02:37:51</span>
    <span class="service">nvidia-drivers</span>
    <span class="message">✓ kernel-headers-installed</span>
  </div>
</div>
```

#### WebSocket API

```go
// Stream boot status updates to web clients
func (s *Server) handleBootStatusWS(w http.ResponseWriter, r *http.Request) {
    conn, _ := upgrader.Upgrade(w, r, nil)
    defer conn.Close()
    
    // Send current status
    status := s.bootMonitor.GetCurrentStatus()
    conn.WriteJSON(status)
    
    // Subscribe to updates
    updates := s.bootMonitor.Subscribe()
    for update := range updates {
        conn.WriteJSON(update)
    }
}

type BootStatus struct {
    Phases      []PhaseStatus   `json:"phases"`
    Services    []ServiceStatus `json:"services"`
    Logs        []LogEntry      `json:"recent_logs"`
    IsComplete  bool           `json:"is_complete"`
    NeedsReboot bool           `json:"needs_reboot"`
}

type ServiceStatus struct {
    Name        string    `json:"name"`
    Phase       string    `json:"phase"`
    Status      string    `json:"status"` // pending, running, completed, failed, rebooting
    LastUpdate  time.Time `json:"last_update"`
    Steps       []string  `json:"completed_steps"`
    CurrentStep string    `json:"current_step,omitempty"`
    NeedsReboot bool      `json:"needs_reboot,omitempty"`
}
```

#### Reboot Handling

```javascript
class BootMonitor {
    constructor() {
        this.ws = null;
        this.reconnectAttempts = 0;
        this.maxReconnectAttempts = 60; // 5 minutes
        this.isRebooting = false;
    }
    
    connect() {
        this.ws = new WebSocket('ws://localhost:8080/api/boot/status');
        
        this.ws.onmessage = (event) => {
            const status = JSON.parse(event.data);
            this.updateUI(status);
            
            // Handle reboot scenarios
            if (status.needs_reboot || status.services.some(s => s.needs_reboot)) {
                this.handlePendingReboot();
            }
            
            if (status.is_complete) {
                this.handleBootComplete();
            }
        };
        
        this.ws.onclose = () => {
            if (!this.isRebooting) {
                this.handleDisconnection();
            }
        };
        
        this.ws.onerror = () => {
            this.handleConnectionError();
        };
    }
    
    handlePendingReboot() {
        this.isRebooting = true;
        this.showRebootMessage("System is rebooting to activate drivers...");
        
        // Start reconnection attempts after expected reboot time
        setTimeout(() => {
            this.attemptReconnection();
        }, 30000); // Wait 30 seconds for reboot
    }
    
    attemptReconnection() {
        if (this.reconnectAttempts < this.maxReconnectAttempts) {
            this.reconnectAttempts++;
            this.updateRebootMessage(`Reconnecting... (${this.reconnectAttempts}/${this.maxReconnectAttempts})`);
            
            // Try to reconnect
            setTimeout(() => {
                this.connect();
            }, 5000);
        } else {
            this.showErrorMessage("Unable to reconnect after reboot. Please refresh the page.");
        }
    }
    
    handleBootComplete() {
        this.isRebooting = false;
        this.showCompletionMessage("🎉 Boot process complete! System is ready.");
    }
    
    showRebootMessage(message) {
        document.getElementById('boot-status').innerHTML = `
            <div class="reboot-overlay">
                <div class="spinner"></div>
                <h2>System Rebooting</h2>
                <p>${message}</p>
                <div class="progress-bar">
                    <div class="progress-fill"></div>
                </div>
            </div>
        `;
    }
    
    updateRebootMessage(message) {
        const overlay = document.querySelector('.reboot-overlay p');
        if (overlay) {
            overlay.textContent = message;
        }
    }
}

// Auto-start monitoring when page loads
window.addEventListener('load', () => {
    new BootMonitor().connect();
});
```

### Service Discovery

The agent reads the boot service configuration to understand the expected phases:

```go
// Load boot-services.yaml at startup
func (m *BootMonitor) loadServiceConfig() error {
    config, err := LoadBootConfig("/etc/zeropoint/boot-services.yaml")
    if err != nil {
        // Fallback to embedded config or defaults
        return m.loadDefaultConfig()
    }
    
    for _, phase := range config.PhaseOrder {
        phaseData := config.Phases[phase]
        m.expectedServices[phase] = phaseData.Services
    }
    return nil
}
```

### Integration Points

#### 1. Agent Service Configuration

The agent service runs with appropriate permissions to read journals:

```ini
[Unit]
Description=Zeropoint Management Agent
After=network.target
Before=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/bin/zeropoint-agent
Restart=always
RestartSec=5
User=root
Group=systemd-journal

[Install]
WantedBy=multi-user.target
```

#### 2. Boot Service Coordination

The agent monitors marker files to detect service completion:

```go
// Monitor for boot completion
func (m *BootMonitor) checkBootCompletion() {
    if _, err := os.Stat("/etc/zeropoint/.boot-complete"); err == nil {
        m.setBootComplete()
        return
    }
    
    // Check individual service markers
    for service := range m.expectedServices {
        markerPath := fmt.Sprintf("/etc/zeropoint/.zeropoint-%s", service)
        if _, err := os.Stat(markerPath); err != nil {
            return // Service not complete yet
        }
    }
}
```

#### 3. Error Handling & Recovery

```go
// Monitor for failed services and suggest recovery
func (m *BootMonitor) handleServiceFailure(service string, err string) {
    // Log failure
    log.Printf("Service %s failed: %s", service, err)
    
    // Check for common failure patterns
    if strings.Contains(err, "No such device or address") {
        m.suggestRecovery(service, "Service may be running too early - check dependencies")
    }
    
    // Notify web clients
    m.broadcast(ServiceUpdate{
        Service: service,
        Status:  "failed", 
        Error:   err,
    })
}
```

## User Experience

### Installation Progress UI

1. **Boot Phase Timeline** - Visual progress through Base → Storage → Utilities → Drivers
2. **Service Details** - Expandable cards showing individual service progress  
3. **Live Logs** - Scrolling log output with syntax highlighting for markers
4. **Estimated Time** - Based on typical service completion times
5. **Error States** - Clear error messages with suggested actions

### Mobile-Responsive Design

The monitoring interface works on mobile devices, allowing users to monitor installation progress remotely via the agent's web interface.

## Technical Benefits

- **Early Visibility** - Monitor progress before SSH/remote access is available
- **Debugging** - Real-time logs help diagnose installation issues
- **User Confidence** - Visual progress prevents "is it working?" uncertainty  
- **Remote Monitoring** - Web interface accessible during headless installations
- **Recovery Assistance** - Automatic error detection and recovery suggestions

This architecture enables the Zeropoint Agent to provide comprehensive boot monitoring while maintaining the structured, phase-based approach to system initialization.