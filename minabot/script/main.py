import datetime
import logging
import socket
import subprocess
import time
from pathlib import Path

from dotenv import dotenv_values
from lxml import html
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.common.exceptions import WebDriverException

# get env_vars
env_vars = dotenv_values("/script/.env")
clock_in_time = datetime.datetime.strptime(env_vars["CLOCK_IN_TIME"], "%H:%M").time()
clock_out_time = datetime.datetime.strptime(env_vars["CLOCK_OUT_TIME"], "%H:%M").time()
# time variance (minutes)
variance = int(env_vars["VARIANCE"])
# offdays in minagine
offdays = ["所休", "法休", "有"]

# Set up the path for log files
log_path = Path(env_vars.get("LOGS_PATH", ""))
log_path.mkdir(exist_ok=True)  # Create the 'logs' directory if it doesn't exist

# Set up logging
log_file = log_path / "script_log.log"

logging.basicConfig(
    level=logging.DEBUG,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[logging.FileHandler(log_file, mode="a"), logging.StreamHandler()],
)


# Logging decorator with retry logic
def log_and_handle_errors(max_retries=3, retry_delay=5):
    def decorator(func):
        def wrapper(*args, **kwargs):
            for attempt in range(max_retries):
                try:
                    logging.info(
                        f"Executing {func.__name__} (attempt {attempt + 1}/{max_retries})"
                    )
                    result = func(*args, **kwargs)
                    logging.info(f"{func.__name__} completed successfully")
                    return result

                except Exception as e:
                    logging.error(
                        f"Error during {func.__name__} (attempt {attempt + 1}/{max_retries}): {e}"
                    )
                    if attempt < max_retries - 1:
                        logging.info(f"Retrying in {retry_delay} seconds...")
                        time.sleep(retry_delay)
                    else:
                        logging.error(
                            f"{func.__name__} failed after {max_retries} attempts"
                        )
                        raise

        return wrapper

    return decorator


# Selenium runs in a sibling container of the home-server compose project,
# started on demand through the mounted docker socket. The compose file and
# .env are mounted read-only so a missing container (e.g. removed by
# `docker system prune`) can be recreated from the single source of truth.
SELENIUM_CONTAINER = "minabot-selenium"
COMPOSE_FILE = "/compose/docker-compose.yml"
COMPOSE_ENV_FILE = "/compose/.env"


def compose_project_name():
    """Read the compose project name off our own container's labels, so the
    recreate command targets the same project regardless of checkout dir.
    (The container hostname is its own container id.)"""
    result = subprocess.run(
        [
            "docker",
            "inspect",
            "-f",
            '{{index .Config.Labels "com.docker.compose.project"}}',
            socket.gethostname(),
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def ensure_selenium_running():
    """Ensure Selenium container is running. Start or create it if needed."""
    try:
        container_name = SELENIUM_CONTAINER

        # Check container status
        result = subprocess.run(
            ["docker", "inspect", "-f", "{{.State.Running}}", container_name],
            capture_output=True,
            text=True,
            check=False,
        )

        if result.returncode != 0:
            # Container doesn't exist - recreate it from the compose file
            logging.info(f"Selenium container '{container_name}' not found, creating it...")
            subprocess.run(
                [
                    "docker",
                    "compose",
                    "--project-name",
                    compose_project_name(),
                    "--env-file",
                    COMPOSE_ENV_FILE,
                    "-f",
                    COMPOSE_FILE,
                    "up",
                    "-d",
                    "--no-deps",
                    SELENIUM_CONTAINER,
                ],
                check=True,
            )
            # Wait for Selenium to be ready
            time.sleep(10)
            logging.info("Selenium container created and ready")
            return

        is_running = result.stdout.strip() == "true"

        if not is_running:
            logging.info(f"Starting Selenium container: {container_name}")
            subprocess.run(["docker", "start", container_name], check=True)
            # Wait for Selenium to be ready
            time.sleep(10)
            logging.info("Selenium container started and ready")
        else:
            logging.info("Selenium container already running")

    except subprocess.CalledProcessError as e:
        logging.error(f"Error managing Selenium container: {e}")
        raise
    except Exception as e:
        logging.error(f"Error managing Selenium container: {e}")
        raise


def stop_selenium():
    """Stop the Selenium container to save resources."""
    try:
        container_name = SELENIUM_CONTAINER

        # Check container status
        result = subprocess.run(
            ["docker", "inspect", "-f", "{{.State.Running}}", container_name],
            capture_output=True,
            text=True,
            check=False,
        )

        if result.returncode != 0:
            logging.warning(f"Selenium container '{container_name}' not found")
            return

        is_running = result.stdout.strip() == "true"

        if is_running:
            logging.info(f"Stopping Selenium container: {container_name}")
            subprocess.run(["docker", "stop", container_name], check=True)
            logging.info("Selenium container stopped")

    except subprocess.CalledProcessError as e:
        logging.error(f"Error stopping Selenium container: {e}")
    except Exception as e:
        logging.error(f"Error stopping Selenium container: {e}")


@log_and_handle_errors(max_retries=3, retry_delay=5)
def login(env_vars):
    # Ensure Selenium is running before attempting to connect
    ensure_selenium_running()

    # Create ChromeOptions object
    chrome_options = webdriver.ChromeOptions()
    # Add the --headless option
    chrome_options.add_argument("--headless")
    chrome_options.add_argument("--disable-gpu")
    chrome_options.add_argument("--no-sandbox")
    chrome_options.add_argument("--disable-dev-shm-usage")

    # Initialize the WebDriver with the configured ChromeOptions
    driver = webdriver.Remote(
        command_executor=f"http://{SELENIUM_CONTAINER}:4444/wd/hub",
        options=chrome_options,
    )
    driver.implicitly_wait(10)

    # Get page
    driver.get("https://tm.minagine.net/index.html")

    # company!
    driver.find_element(By.NAME, "user[cntrctr_dmn]").clear()
    driver.find_element(By.NAME, "user[cntrctr_dmn]").send_keys(env_vars["COMPANY"])
    # id
    driver.find_element(By.NAME, "user[login]").clear()
    driver.find_element(By.NAME, "user[login]").send_keys(env_vars["ID"])
    # password
    driver.find_element(By.NAME, "user[password]").clear()
    driver.find_element(By.NAME, "user[password]").send_keys(env_vars["PASS"])
    # commit
    driver.find_element(By.NAME, "commit").click()

    return driver


@log_and_handle_errors(max_retries=3, retry_delay=5)
def clock_in(env_vars):
    driver = None
    try:
        driver = login(env_vars)
        # Click clock-in button
        driver.find_element(By.ID, "button0").click()
        logging.info("Clock-in successful")
    finally:
        if driver:
            driver.quit()


@log_and_handle_errors(max_retries=3, retry_delay=5)
def clock_out(env_vars):
    driver = None
    try:
        driver = login(env_vars)
        # Click clock-out button
        driver.find_element(By.ID, "button1").click()
        logging.info("Clock-out successful")
    finally:
        if driver:
            driver.quit()


@log_and_handle_errors(max_retries=3, retry_delay=10)
def check_if_working_day(env_vars):
    """Check if today is a working day on minagine using lxml instead of pandas."""
    driver = None
    try:
        driver = login(env_vars)
        driver.get("https://tm.minagine.net/work/wrktimemngmntshtself/sht")

        # Parse HTML with lxml
        tree = html.fromstring(driver.page_source)

        # Find all tables - the worksheet is typically in the 5th table (index 4)
        tables = tree.xpath("//table")

        if len(tables) < 5:
            logging.error(f"Expected at least 5 tables, found {len(tables)}")
            return True  # Default to working day if we can't determine

        # Get the 5th table (index 4) - the worksheet table
        worksheet_table = tables[4]

        # Get all rows
        rows = worksheet_table.xpath(".//tr")

        # Get today's date
        today = datetime.datetime.now().date().day

        # Search for the row that matches today's day number
        # This is more robust than using a fixed offset
        for row in rows:
            cells = row.xpath(".//td")

            # Check if first cell contains today's day number
            if len(cells) > 0:
                first_cell = cells[0].text_content().strip()

                if first_cell == str(today):
                    # Found the correct row for today
                    # Column 2 (index 2) contains the day type
                    if len(cells) > 2:
                        cell_text = cells[2].text_content().strip()
                        logging.info(f"Day type for day {today}: '{cell_text}'")

                        # Empty string or not in offdays list means working day
                        if cell_text and cell_text in offdays:
                            logging.info("Today is an off day")
                            return False
                        else:
                            logging.info("Today is a working day")
                            return True

        # Default to working day if we can't determine
        logging.warning(
            f"Could not find row for day {today}, defaulting to working day"
        )
        return True

    finally:
        if driver:
            driver.quit()


@log_and_handle_errors(max_retries=1, retry_delay=0)
def clock_loop(
    env_vars, clock_in_func, clock_out_func, clock_in_time, clock_out_time, variance
):
    """
    Check time every 10 seconds and do clock-in or clock-out.
    Starts Selenium well before the actual execution time to ensure it's ready.
    """
    import random

    # Generate random offset
    random_offset = random.randint(-variance, variance)

    # Calculate target times with offset
    clock_in_target = datetime.datetime.combine(
        datetime.date.today(), clock_in_time
    ) + datetime.timedelta(minutes=random_offset)

    clock_out_target = datetime.datetime.combine(
        datetime.date.today(), clock_out_time
    ) + datetime.timedelta(minutes=random_offset)

    targets = [
        (clock_in_target, clock_in_func, "clock-in"),
        (clock_out_target, clock_out_func, "clock-out"),
    ]

    # Pre-start Selenium 5 minutes before first target to ensure it's ready
    selenium_start_buffer = datetime.timedelta(minutes=5)
    earliest_target = min(t[0] for t in targets)
    selenium_start_time = earliest_target - selenium_start_buffer

    done = False

    # log entry
    logging.info(
        f"Waiting loop started. Clock-in target: {clock_in_target.strftime('%H:%M')}, "
        f"Clock-out target: {clock_out_target.strftime('%H:%M')}, "
        f"Random offset: {random_offset} minutes"
    )
    logging.info(f"Selenium will start at {selenium_start_time.strftime('%H:%M:%S')}")

    selenium_started = False

    while True:
        current_time = datetime.datetime.now()

        if done:
            break

        # Start Selenium container 5 minutes before first target
        if not selenium_started and current_time >= selenium_start_time:
            logging.info("Pre-starting Selenium container to ensure it's ready...")
            try:
                ensure_selenium_running()
                selenium_started = True
                logging.info("Selenium container pre-started successfully")
            except Exception as e:
                logging.error(f"Failed to pre-start Selenium: {e}")

        # Check if it's time to execute any target
        for target_time, func, action_name in targets:
            if (
                current_time.hour == target_time.hour
                and current_time.minute == target_time.minute
            ):
                logging.info(
                    f"Executing {action_name} at {current_time.strftime('%H:%M:%S')}"
                )
                func(env_vars)
                done = True
                break

        time.sleep(10)

    # Stop Selenium after tasks complete to save resources
    logging.info("All tasks completed, stopping Selenium container...")
    stop_selenium()


# Main execution
if __name__ == "__main__":
    try:
        if check_if_working_day(env_vars):
            clock_loop(
                env_vars, clock_in, clock_out, clock_in_time, clock_out_time, variance
            )
        else:
            logging.info("Today is not a working day. Skipping clock-in/out.")
            # Stop Selenium since we don't need it
            stop_selenium()
    except Exception as e:
        logging.error(f"Fatal error in main execution: {e}")
        # Ensure Selenium is stopped even if there's an error
        stop_selenium()
        raise
