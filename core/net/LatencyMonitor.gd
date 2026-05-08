class_name LatencyMonitor
extends Node

signal latency_updated(ms: float)
signal high_latency_warning(ms: float)   ## > 200ms
signal disconnection_risk(ms: float)     ## > 5000ms

const PING_INTERVAL   := 3.0
const WARN_THRESHOLD  := 200.0
const DISCO_THRESHOLD := 5000.0

var current_latency_ms: float = 0.0
var _ping_timer: float = 0.0
var _client  # NetworkGameClient

func _process(delta: float) -> void:
	if _client == null or not NetworkManager.is_connected_to_game:
		return
	_ping_timer += delta
	if _ping_timer >= PING_INTERVAL:
		_ping_timer = 0.0
		_client.send_ping()

func update_latency(rtt_ms: float) -> void:
	current_latency_ms = rtt_ms
	latency_updated.emit(rtt_ms)
	if rtt_ms > DISCO_THRESHOLD:
		disconnection_risk.emit(rtt_ms)
	elif rtt_ms > WARN_THRESHOLD:
		high_latency_warning.emit(rtt_ms)

func set_client(client) -> void:  # NetworkGameClient
	_client = client
