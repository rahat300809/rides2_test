import paramiko
import sys
import time
import os

sys.stdout.reconfigure(encoding='utf-8')

HOST = os.environ.get('DEPLOY_HOST', '192.168.0.114')
USER = os.environ.get('DEPLOY_USER', 'rahat')
PASSWORD = os.environ.get('DEPLOY_PASS', 'rahat')

print(f"Connecting to {USER}@{HOST}...")

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

connected = False
for attempt in range(1, 4):
    try:
        ssh.connect(HOST, username=USER, password=PASSWORD, timeout=12, banner_timeout=30)
        connected = True
        print("Connected successfully!\n")
        break
    except Exception as e:
        print(f"Connection attempt {attempt} failed: {e}")
        if attempt < 3:
            time.sleep(2)

if not connected:
    print(f"\n❌ Could not connect to {USER}@{HOST}. Ensure host is powered on and SSH service is running.")
    sys.exit(1)

def run(cmd, desc=''):
    print(f"==================================================")
    print(f"🚀 {desc or cmd}")
    print(f"==================================================")
    stdin, stdout, stderr = ssh.exec_command(cmd)
    out = stdout.read().decode('utf-8', errors='replace')
    err = stderr.read().decode('utf-8', errors='replace')
    if out.strip():
        print(out.strip())
    if err.strip():
        print(f"[STDERR]: {err.strip()}")
    print()
    return out

# 1. Back up database and existing completed trips
run('mkdir -p /home/rahat/backups && cp -r /home/rahat/diu_ride/server/rides.db* /home/rahat/backups/ 2>/dev/null || true', '1. Backing up SQLite database')
run('cp /home/rahat/diu_ride/server/completed_trips.csv /home/rahat/backups/completed_trips.csv.bak 2>/dev/null || true', '2. Backing up completed trips CSV')

# 2. Sync to latest origin/main
run('cd /home/rahat/diu_ride && git reset --hard HEAD && git clean -fd && git fetch origin && git reset --hard origin/main && git log -n 2 --oneline', '3. Syncing repo to origin/main')

# 3. Preserve trips
merge_script = """
import os
bak = '/home/rahat/backups/completed_trips.csv.bak'
cur = '/home/rahat/diu_ride/server/completed_trips.csv'
if os.path.exists(bak) and os.path.exists(cur):
    with open(bak, 'r', encoding='utf-8') as f:
        bak_lines = [l for l in f.read().splitlines() if l.strip()]
    with open(cur, 'r', encoding='utf-8') as f:
        cur_lines = [l for l in f.read().splitlines() if l.strip()]
    cur_set = set(cur_lines)
    added = 0
    with open(cur, 'a', encoding='utf-8') as f:
        for line in bak_lines:
            if line not in cur_set:
                f.write(line + '\\n')
                added += 1
    print(f'Preserved and merged {added} trips from backup.')
"""
run(f"python3 -c \"{merge_script}\"", '4. Merging runtime completed trips')

# 4. Check Docker deployment & ensure Docker is installed
docker_check = run('which docker || echo rahat | sudo -S which docker || true', '5. Checking Docker presence')

if 'docker' not in docker_check.lower():
    print("📦 Installing Docker on Ubuntu server...")
    run('echo rahat | sudo -S apt-get update -y && echo rahat | sudo -S apt-get install -y docker.io docker-compose-v2 && echo rahat | sudo -S usermod -aG docker rahat && echo rahat | sudo -S systemctl enable --now docker', 'Installing Docker & Docker Compose')

print("🐳 Deploying project with Docker Compose...")
run('echo rahat | sudo -S systemctl stop diu-ride.service 2>/dev/null || true', 'Stopping legacy systemd service')
run('echo rahat | sudo -S fuser -k 8001/tcp 8080/tcp 2>/dev/null || true', 'Freeing up ports 8001 and 8080')
run('cd /home/rahat/diu_ride && echo rahat | sudo -S docker compose down 2>/dev/null || true', 'Stopping old containers')
run('cd /home/rahat/diu_ride && echo rahat | sudo -S docker compose up -d --build', 'Building and launching Docker containers')
time.sleep(5)
run('echo rahat | sudo -S docker ps', 'Checking running Docker containers')

# 5. Test endpoints
run('curl -s http://127.0.0.1:8001/ride/health', 'Testing /ride/health')
run('curl -s http://127.0.0.1:8001/ride/api/admin/ai-settings', 'Testing /ride/api/admin/ai-settings')
run('curl -s http://127.0.0.1:8001/ride/api/spatial/dropping-zones', 'Testing /ride/api/spatial/dropping-zones')
run('curl -s "http://127.0.0.1:8001/ride/api/rides/suggest-nearest?lat=23.8069&lng=90.3687&target_name=Mirpur+10"', 'Testing /ride/api/rides/suggest-nearest')
run('curl -s -I http://127.0.0.1:8001/ride/ | head -n 12', 'Testing /ride/ web header')

ssh.close()
print("🎉 Remote deployment successfully finished!")
