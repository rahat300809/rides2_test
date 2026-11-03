import os
import sys
import paramiko

SERVER_IP = "192.168.0.114"
SERVER_PORT = 22
SERVER_USER = "rahat"
SERVER_PASS = "rahat"
REMOTE_DIR = "/home/rahat/diu_ride"

def run_remote_deploy():
    local_bundle = os.path.join(os.path.dirname(__file__), "deploy_diff.bundle")
    if not os.path.isfile(local_bundle):
        print(f"ERROR: Bundle not found at {local_bundle}.")
        sys.exit(1)

    print(f">> Connecting to {SERVER_USER}@{SERVER_IP}...")
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        ssh.connect(SERVER_IP, port=SERVER_PORT, username=SERVER_USER, password=SERVER_PASS, timeout=10)
        print("Connected successfully!\n")
    except Exception as e:
        print(f"ERROR: Connection failed: {e}")
        sys.exit(1)

    # 1. Upload bundle via SFTP (preserve live remote database!)
    remote_bundle = f"{REMOTE_DIR}/server/deploy_diff.bundle"
    print(">> Uploading deploy_diff.bundle via SFTP (preserving live database)...")
    sftp = ssh.open_sftp()
    sftp.put(local_bundle, remote_bundle)
    sftp.close()
    print("Bundle uploaded successfully!\n")

    # 2. Update repository from bundle
    git_script = f"""
cd {REMOTE_DIR}
git fetch server/deploy_diff.bundle '+refs/heads/*:refs/remotes/bundle/*'
git reset --hard bundle/main
git submodule update --init --recursive


echo "LATEST COMMITS ON SERVER:"
git log -n 2 --oneline
echo "INDEX.HTML BASE HREF:"
grep -n "base href" {REMOTE_DIR}/server/web_build/index.html
"""
    print(">> Applying incremental update on server")
    stdin, stdout, stderr = ssh.exec_command(git_script)
    out = stdout.read().decode('utf-8', errors='replace')
    err = stderr.read().decode('utf-8', errors='replace')
    print(out)
    if err and "warning" not in err.lower():
        print(f"Git Notice: {err}")

    # 3. Restart server process
    print(">> Restarting diu-ride.service")
    cmd = "echo rahat | sudo -S systemctl restart diu-ride.service && sleep 2 && systemctl status diu-ride.service --no-pager"
    stdin, stdout, stderr = ssh.exec_command(cmd)
    service_out = stdout.read().decode('utf-8', errors='replace')
    try:
        print(service_out)
    except Exception:
        print(service_out.encode('ascii', errors='replace').decode('ascii'))

    # 4. Health checks
    print(">> Testing API health")
    stdin, stdout, stderr = ssh.exec_command("curl -s http://127.0.0.1:8001/ride/health")
    print(stdout.read().decode('utf-8', errors='replace'))

    print(">> Testing /ride/ header")
    stdin, stdout, stderr = ssh.exec_command("curl -s -I http://127.0.0.1:8001/ride/")
    print(stdout.read().decode('utf-8', errors='replace'))

    ssh.close()
    print("\n** Incremental deployment complete! **")

if __name__ == "__main__":
    run_remote_deploy()
