import paramiko
import os
import sys

HOST = "8.130.49.62"
PORT = 22
USER = "root"
PASS = "Zhangrui513@"
REMOTE_DIR = "/opt/game_server"
SERVICE = "game_server"

LOCAL_FILES = [
    r"D:\Godot Export\Server\game_server.x86_64",
    r"D:\Godot Export\Server\game_server.pck",
]

def run(ssh, cmd):
    print(f"  $ {cmd}")
    _, stdout, stderr = ssh.exec_command(cmd)
    out = stdout.read().decode().strip()
    err = stderr.read().decode().strip()
    if out:
        print(f"    {out}")
    if err:
        print(f"    [err] {err}")
    return out

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
print(f"连接 {HOST}...")
ssh.connect(HOST, PORT, USER, PASS, timeout=15)
print("连接成功")

run(ssh, f"mkdir -p {REMOTE_DIR}")
run(ssh, f"systemctl stop {SERVICE} 2>/dev/null || true")

sftp = ssh.open_sftp()
for local in LOCAL_FILES:
    name = os.path.basename(local)
    remote = f"{REMOTE_DIR}/{name}"
    size = os.path.getsize(local)
    print(f"上传 {name}  ({size/1024/1024:.1f} MB)...")
    sftp.put(local, remote)
    print(f"  完成")
sftp.close()

run(ssh, f"chmod +x {REMOTE_DIR}/game_server.x86_64")
run(ssh, f"systemctl start {SERVICE}")
import time; time.sleep(2)
run(ssh, f"systemctl status {SERVICE} --no-pager -l")

ssh.close()
print("部署完成")
