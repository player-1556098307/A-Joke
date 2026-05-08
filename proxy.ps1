param([int]$Port = 8080)

Add-Type -AssemblyName System.Net.Http

$TARGET_BASE = "https://api.deepseek.com/anthropic"
$API_KEY     = "sk-9c91b48aef564e7da39b7da989d24371"

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "Proxy on http://localhost:$Port -> $TARGET_BASE  (Ctrl+C to stop)"

$client = [System.Net.Http.HttpClient]::new()
$client.Timeout = [TimeSpan]::FromMinutes(10)

try {
    while ($true) {
        $ctx = $listener.GetContext()
        $req = $ctx.Request
        $res = $ctx.Response
        try {
            # Read body
            $body = [System.IO.StreamReader]::new($req.InputStream).ReadToEnd()

            # Sanitize user_id
            if ($body) {
                $json = $body | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($json -and $json.PSObject.Properties["user_id"] -and $json.user_id) {
                    $json.user_id = $json.user_id -replace '[^a-zA-Z0-9_-]', '_'
                    $body = $json | ConvertTo-Json -Depth 20 -Compress
                }
            }

            # Build upstream request
            $msg = [System.Net.Http.HttpRequestMessage]::new(
                [System.Net.Http.HttpMethod]::new($req.HttpMethod),
                ($TARGET_BASE + $req.RawUrl))
            $msg.Headers.TryAddWithoutValidation("Authorization", "Bearer $API_KEY") | Out-Null

            foreach ($k in $req.Headers.AllKeys) {
                if ($k -notin @("Host","Authorization","Content-Length","Content-Type","Transfer-Encoding")) {
                    $msg.Headers.TryAddWithoutValidation($k, $req.Headers[$k]) | Out-Null
                }
            }
            if ($body -and $req.HttpMethod -ne "GET") {
                $msg.Content = [System.Net.Http.StringContent]::new(
                    $body, [Text.Encoding]::UTF8, "application/json")
            }

            # Forward and stream response
            $up = $client.SendAsync($msg, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
            $res.StatusCode = [int]$up.StatusCode

            foreach ($h in $up.Headers) {
                if ($h.Key -notin @("Transfer-Encoding","Content-Length")) {
                    try { $res.Headers[$h.Key] = [string]::Join(",",$h.Value) } catch {}
                }
            }
            foreach ($h in $up.Content.Headers) {
                if ($h.Key -notin @("Transfer-Encoding","Content-Length")) {
                    try { $res.Headers[$h.Key] = [string]::Join(",",$h.Value) } catch {}
                }
            }

            $stream = $up.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
            $buf = [byte[]]::new(8192)
            do {
                $n = $stream.Read($buf, 0, $buf.Length)
                if ($n -gt 0) {
                    $res.OutputStream.Write($buf, 0, $n)
                    $res.OutputStream.Flush()
                }
            } while ($n -gt 0)
        }
        catch { Write-Warning "Error: $_"; try { $res.StatusCode = 502 } catch {} }
        finally { try { $res.OutputStream.Close() } catch {} }
    }
}
finally { $listener.Stop(); Write-Host "Proxy stopped." }
