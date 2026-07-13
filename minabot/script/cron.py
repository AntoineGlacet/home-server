import datetime
import logging
import sys
from pathlib import Path

from crontab import CronTab
from dotenv import dotenv_values

# Load environment variables from the .env file
env_vars = dotenv_values(".env")

# Required environment variables
REQUIRED_ENV_VARS = [
    "LOGS_PATH",
    "VARIANCE",
    "SCRIPT_PATH",
    "CLOCK_IN_TIME",
    "CLOCK_OUT_TIME",
    "PYTHON_PATH",
    "COMPANY",
    "ID",
    "PASS",
]

# Validate environment variables
missing_vars = [var for var in REQUIRED_ENV_VARS if not env_vars.get(var)]
if missing_vars:
    print(f"ERROR: Missing required environment variables: {', '.join(missing_vars)}")
    sys.exit(1)

# Set up logging path
log_path = Path(env_vars.get("LOGS_PATH", ""))
log_path.mkdir(exist_ok=True)  # Create the 'logs' directory if it doesn't exist

# Set up logging
log_file = log_path / "cron_script.log"

logging.basicConfig(
    level=logging.DEBUG,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler(log_file, mode="a"),
        logging.StreamHandler(sys.stdout),
    ],
)


def add_cron_job(
    cron,
    script_path,
    cron_schedule,
    python_path=env_vars.get("PYTHON_PATH", ""),
):
    script_path = Path(script_path)

    # Define the cron schedule. Output goes to the log file AND the
    # container's stdout (/proc/1/fd/1) so runs show up in `docker logs`
    # and get shipped to Loki by promtail.
    job_command = (
        f"{python_path} {script_path} 2>&1 "
        f"| tee -a {log_file} > /proc/1/fd/1"
    )
    job = cron.new(command=job_command)
    job.setall(cron_schedule)

    # Write the cron job to the crontab
    cron.write()
    logging.info(f"Cron job added: {job_command} - Schedule: {cron_schedule}")


def activate():
    variance = int(env_vars["VARIANCE"])
    script_path = env_vars.get("SCRIPT_PATH", "")
    time_job1 = datetime.datetime.strptime(
        env_vars["CLOCK_IN_TIME"], "%H:%M"
    ) - datetime.timedelta(minutes=2 * variance)
    time_job2 = datetime.datetime.strptime(
        env_vars["CLOCK_OUT_TIME"], "%H:%M"
    ) - datetime.timedelta(minutes=2 * variance)

    # Set up cron jobs
    cron = CronTab(user=True)  # Use the current user's crontab

    for time in [time_job1, time_job2]:
        hour = time.time().hour
        minute = time.time().minute
        cron_schedule = f"{minute} {hour} * * *"  # Every day at the specified time
        add_cron_job(cron, script_path, cron_schedule)


def stop():
    # Remove cron jobs
    cron = CronTab(user=True)  # Use the current user's crontab
    cron.remove_all(
        command=f"{env_vars.get('PYTHON_PATH', '')} {env_vars.get('SCRIPT_PATH', '')}"
    )
    cron.write()
    logging.info(f"Cron jobs removed for: {env_vars.get('SCRIPT_PATH', '')}")


# Example usage:
# To activate the cron jobs
stop()
activate()

# To stop (remove) the cron jobs
# stop()
