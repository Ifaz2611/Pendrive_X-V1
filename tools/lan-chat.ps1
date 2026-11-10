# ================================================================
# Pendrive_X - lightweight LAN chat page for Ollama (Windows)
# ================================================================
# Serves a small mobile-friendly chat UI and proxies requests to
# the Ollama instance running on this PC. Uses a raw TcpListener so
# it does NOT need admin rights / an HttpListener URL reservation.
#
# Usage:
#   powershell -NoProfile -File tools\lan-chat.ps1 -Port 8090 `
#       -OllamaUrl http://127.0.0.1:11434 -Model nemomix-local
# ================================================================
param(
    [int]$Port = 8090,
    [string]$OllamaUrl = "http://127.0.0.1:11434",
    [string]$Model = "",
    [string]$BindAddress = "0.0.0.0",
    [string]$LogFile = "",
    [switch]$Start
)

$ErrorActionPreference = "Stop"
$OllamaUrl = $OllamaUrl.TrimEnd('/')

# Re-launch in the background and print the child PID (used by the .bat).
if ($Start) {
    $argList = @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath,
        "-Port", "$Port",
        "-OllamaUrl", $OllamaUrl,
        "-Model", $Model,
        "-BindAddress", $BindAddress
    )
    if ($LogFile) { $argList += @("-LogFile", $LogFile) }
    $child = Start-Process -FilePath "powershell.exe" -ArgumentList $argList -WindowStyle Hidden -PassThru
    Write-Output $child.Id
    exit 0
}

function Write-Log {
    param([string]$Message)
    if (-not $LogFile) { return }
    try {
        $dir = Split-Path -Parent $LogFile
        if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        Add-Content -LiteralPath $LogFile -Value ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message) -Encoding UTF8
    } catch { }
}

# -----------------------------------------------------------------
# Static chat page (no external assets, works on phones)
# -----------------------------------------------------------------
$ChatHtml = @'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>Pendrive_X Chat</title>
<style>
  :root { color-scheme: dark; --bg:#0b0f14; --panel:#121924; --accent:#31d0aa; --text:#e8f0f8; --muted:#8fa3b8; }
  * { box-sizing: border-box; }
  body { margin:0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
         background: radial-gradient(1200px 600px at 20% -10%, #123 0%, var(--bg) 55%);
         color:var(--text); height:100dvh; display:flex; flex-direction:column; }
  header { padding:14px 16px; display:flex; align-items:center; gap:10px;
           border-bottom:1px solid #1d2938; background:#0b0f14cc; backdrop-filter: blur(8px); }
  header .dot { width:9px; height:9px; border-radius:50%; background:var(--accent); box-shadow:0 0 12px var(--accent); }
  header h1 { font-size:15px; margin:0; font-weight:600; letter-spacing:.02em; }
  header .model { margin-left:auto; font-size:11px; color:var(--muted); max-width:45%; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
  main { flex:1; overflow-y:auto; padding:16px; display:flex; flex-direction:column; gap:10px; }
  .msg { max-width:86%; padding:10px 13px; border-radius:16px; line-height:1.45; font-size:15px; white-space:pre-wrap; word-wrap:break-word; }
  .user { align-self:flex-end; background:linear-gradient(135deg,#1f8f78,#2bbd99); color:#04120e; border-bottom-right-radius:5px; }
  .bot { align-self:flex-start; background:var(--panel); border:1px solid #1e2a3a; border-bottom-left-radius:5px; }
  .bot.typing { color:var(--muted); font-style:italic; }
  footer { padding:10px 12px calc(10px + env(safe-area-inset-bottom)); border-top:1px solid #1d2938; background:#0b0f14; }
  .row { display:flex; gap:8px; align-items:flex-end; }
  textarea { flex:1; resize:none; min-height:44px; max-height:140px; padding:11px 13px; border-radius:14px;
             border:1px solid #24344a; background:#0e1520; color:var(--text); font:inherit; outline:none; }
  textarea:focus { border-color:#2bbd99; }
  button { height:44px; padding:0 18px; border:0; border-radius:14px; background:var(--accent); color:#04120e;
           font-weight:700; font-size:14px; }
  button:disabled { opacity:.45; }
  .hint { text-align:center; color:var(--muted); font-size:11px; margin-top:7px; }
</style>
</head>
<body>
<header>
  <span class="dot"></span>
  <h1>Pendrive_X</h1>
  <span class="model" id="model">local</span>
</header>
<main id="messages">
  <div class="msg bot">Hi! This chat runs on the USB computer. Ask me anything.</div>
</main>
<footer>
  <div class="row">
    <textarea id="input" rows="1" placeholder="Message..." autocomplete="off"></textarea>
    <button id="send">Send</button>
  </div>
  <div class="hint">On your local network - keep the USB computer awake</div>
</footer>
<script>
const messages = document.getElementById('messages');
const input = document.getElementById('input');
const send = document.getElementById('send');
const modelLabel = document.getElementById('model');
let model = "__MODEL__";
let busy = false;

fetch('/api/models').then(r => r.json()).then(data => {
  const models = (data.models || []).map(m => m.name);
  if (!model && models.length) model = models[0];
  if (model) modelLabel.textContent = model;
}).catch(() => {});

function bubble(text, cls) {
  const div = document.createElement('div');
  div.className = 'msg ' + cls;
  div.textContent = text;
  messages.appendChild(div);
  messages.scrollTop = messages.scrollHeight;
  return div;
}

function resize() {
  input.style.height = 'auto';
  input.style.height = Math.min(input.scrollHeight, 140) + 'px';
}
input.addEventListener('input', resize);
input.addEventListener('keydown', e => {
  if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); submit(); }
});
send.addEventListener('click', submit);

async function submit() {
  const text = input.value.trim();
  if (!text || busy) return;
  busy = true; send.disabled = true;
  input.value = ''; resize();
  bubble(text, 'user');
  const pending = bubble('Thinking...', 'bot typing');
  try {
    const res = await fetch('/api/chat', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({ model: model, messages: [{role:'user', content:text}], stream:false })
    });
    const data = await res.json();
    const reply = (data.message && data.message.content) || data.error || 'No response';
    pending.classList.remove('typing');
    pending.textContent = reply;
  } catch (err) {
    pending.classList.remove('typing');
    pending.textContent = 'Connection error: ' + err.message;
  } finally {
    busy = false; send.disabled = false; input.focus();
    messages.scrollTop = messages.scrollHeight;
  }
}
</script>
</body>
</html>
'@

# -----------------------------------------------------------------
# HTTP helpers
# -----------------------------------------------------------------
function Read-HttpRequest {
    param([System.Net.Sockets.NetworkStream]$Stream)
    $reader = New-Object System.IO.StreamReader($Stream, [System.Text.Encoding]::UTF8, $false, 1024, $true)
    $requestLine = $reader.ReadLine()
    if ([string]::IsNullOrWhiteSpace($requestLine)) { return $null }

    $parts = $requestLine -split ' '
    if ($parts.Count -lt 2) { return $null }
    $method = $parts[0].ToUpperInvariant()
    $path = $parts[1].Split('?')[0]

    $headers = @{}
    while ($true) {
        $line = $reader.ReadLine()
        if ($null -eq $line -or $line -eq "") { break }
        $idx = $line.IndexOf(':')
        if ($idx -gt 0) {
            $headers[$line.Substring(0, $idx).Trim().ToLowerInvariant()] = $line.Substring($idx + 1).Trim()
        }
    }

    $body = ""
    $length = 0
    if ($headers.ContainsKey("content-length")) { [void][int]::TryParse($headers["content-length"], [ref]$length) }
    if ($length -gt 0) {
        $buffer = New-Object char[] $length
        $read = 0
        while ($read -lt $length) {
            $n = $reader.Read($buffer, $read, $length - $read)
            if ($n -le 0) { break }
            $read += $n
        }
        if ($read -gt 0) { $body = -join $buffer[0..($read - 1)] }
    }

    return @{ Method = $method; Path = $path; Body = $body }
}

function Send-HttpResponse {
    param(
        [System.Net.Sockets.NetworkStream]$Stream,
        [int]$Status = 200,
        [string]$ContentType = "application/json; charset=utf-8",
        [string]$Body = ""
    )
    $reason = @{ 200 = "OK"; 400 = "Bad Request"; 404 = "Not Found"; 405 = "Method Not Allowed"; 500 = "Internal Server Error" }
    $reasonText = if ($reason.ContainsKey($Status)) { $reason[$Status] } else { "OK" }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $header = "HTTP/1.1 $Status $reasonText`r`n" +
              "Content-Type: $ContentType`r`n" +
              "Content-Length: $($bytes.Length)`r`n" +
              "Cache-Control: no-store`r`n" +
              "Connection: close`r`n`r`n"
    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    if ($bytes.Length -gt 0) { $Stream.Write($bytes, 0, $bytes.Length) }
    $Stream.Flush()
}

function Invoke-Ollama {
    param([string]$Path, [string]$Method = "GET", [string]$Body = "")
    $uri = "$OllamaUrl$Path"
    if ($Method -eq "GET") {
        return Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 120
    }
    return Invoke-RestMethod -Uri $uri -Method Post -Body $Body -ContentType "application/json" -TimeoutSec 600
}

# -----------------------------------------------------------------
# Request loop
# -----------------------------------------------------------------
$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Parse($BindAddress), $Port)
$listener.Start()
Write-Log "LAN chat listening on ${BindAddress}:${Port} -> $OllamaUrl (model=$Model)"
Write-Host "[OK] LAN chat page: http://${BindAddress}:${Port}/ (proxying $OllamaUrl)"

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $client.ReceiveTimeout = 30000
            $stream = $client.GetStream()
            $request = Read-HttpRequest -Stream $stream
            if (-not $request) { continue }

            switch ($request.Path) {
                "/" { Send-HttpResponse -Stream $stream -ContentType "text/html; charset=utf-8" -Body ($ChatHtml -replace '__MODEL__', $Model) }
                "/health" { Send-HttpResponse -Stream $stream -Body '{"status":"ok"}' }
                "/api/models" {
                    try {
                        $tags = Invoke-Ollama -Path "/api/tags"
                        Send-HttpResponse -Stream $stream -Body ($tags | ConvertTo-Json -Depth 10 -Compress)
                    } catch {
                        Send-HttpResponse -Stream $stream -Status 500 -Body '{"error":"Ollama is not reachable"}'
                    }
                }
                "/api/chat" {
                    if ($request.Method -ne "POST") {
                        Send-HttpResponse -Stream $stream -Status 405 -Body '{"error":"POST required"}'
                    } else {
                        try {
                            $payload = $request.Body | ConvertFrom-Json
                            if (-not $payload.model -and $Model) { $payload | Add-Member -NotePropertyName model -NotePropertyValue $Model -Force }
                            $json = $payload | ConvertTo-Json -Depth 20 -Compress
                            $reply = Invoke-Ollama -Path "/api/chat" -Method "POST" -Body $json
                            Send-HttpResponse -Stream $stream -Body ($reply | ConvertTo-Json -Depth 20 -Compress)
                        } catch {
                            Send-HttpResponse -Stream $stream -Status 500 -Body ('{"error":"' + ($_.Exception.Message -replace '"', "'") + '"}')
                        }
                    }
                }
                default { Send-HttpResponse -Stream $stream -Status 404 -Body '{"error":"not found"}' }
            }
        } catch {
            Write-Log "Request error: $_"
        } finally {
            try { $client.Close() } catch { }
        }
    }
} finally {
    try { $listener.Stop() } catch { }
    Write-Log "LAN chat stopped"
}
