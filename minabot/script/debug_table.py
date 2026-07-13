import datetime
import logging
import subprocess
import time
from pathlib import Path

from dotenv import dotenv_values
from lxml import html
from selenium import webdriver
from selenium.webdriver.common.by import By

# get env_vars
env_vars = dotenv_values("/script/.env")

# Set up logging
logging.basicConfig(
    level=logging.DEBUG,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler()],
)


def ensure_selenium_running():
    """Ensure Selenium container is running. Start it if it's not."""
    try:
        container_name = "minabot-selenium-1"
        result = subprocess.run(
            ["docker", "inspect", "-f", "{{.State.Running}}", container_name],
            capture_output=True,
            text=True,
            check=False,
        )

        if result.returncode != 0:
            logging.error(f"Selenium container '{container_name}' not found")
            raise Exception(f"Container {container_name} does not exist")

        is_running = result.stdout.strip() == "true"

        if not is_running:
            logging.info(f"Starting Selenium container: {container_name}")
            subprocess.run(["docker", "start", container_name], check=True)
            time.sleep(10)
            logging.info("Selenium container started and ready")
        else:
            logging.info("Selenium container already running")

    except Exception as e:
        logging.error(f"Error managing Selenium container: {e}")
        raise


def login(env_vars):
    ensure_selenium_running()

    chrome_options = webdriver.ChromeOptions()
    chrome_options.add_argument("--headless")
    chrome_options.add_argument("--disable-gpu")
    chrome_options.add_argument("--no-sandbox")
    chrome_options.add_argument("--disable-dev-shm-usage")

    driver = webdriver.Remote(
        command_executor="http://selenium:4444/wd/hub", options=chrome_options
    )
    driver.implicitly_wait(10)
    driver.get("https://tm.minagine.net/index.html")

    driver.find_element(By.NAME, "user[cntrctr_dmn]").clear()
    driver.find_element(By.NAME, "user[cntrctr_dmn]").send_keys(env_vars["COMPANY"])
    driver.find_element(By.NAME, "user[login]").clear()
    driver.find_element(By.NAME, "user[login]").send_keys(env_vars["ID"])
    driver.find_element(By.NAME, "user[password]").clear()
    driver.find_element(By.NAME, "user[password]").send_keys(env_vars["PASS"])
    driver.find_element(By.NAME, "commit").click()

    return driver


def debug_table_structure():
    """Debug the table structure to understand proper indexing."""
    driver = None
    try:
        driver = login(env_vars)
        driver.get("https://tm.minagine.net/work/wrktimemngmntshtself/sht")

        # Parse HTML with lxml
        tree = html.fromstring(driver.page_source)

        # Find all tables
        tables = tree.xpath("//table")
        logging.info(f"Found {len(tables)} tables on the page")

        if len(tables) < 5:
            logging.error(f"Expected at least 5 tables, found {len(tables)}")
            return

        # Get the 5th table (index 4) - the worksheet table
        worksheet_table = tables[4]

        # Get all rows
        rows = worksheet_table.xpath(".//tr")
        logging.info(f"\n{'=' * 80}")
        logging.info(f"WORKSHEET TABLE ANALYSIS (Table 5, index 4)")
        logging.info(f"Total rows: {len(rows)}")
        logging.info(f"{'=' * 80}\n")

        # Analyze each row
        for idx, row in enumerate(rows):
            cells = row.xpath(".//td | .//th")

            # Get text content from each cell
            cell_contents = []
            for cell in cells:
                text = cell.text_content().strip()
                # Replace newlines and extra spaces
                text = " ".join(text.split())
                cell_contents.append(text)

            logging.info(
                f"Row {idx:2d} ({len(cells):2d} cells): {cell_contents[:10]}"
            )  # Show first 10 cells

            # Special attention to rows that might contain day numbers
            if len(cells) > 0:
                first_cell = cell_contents[0] if cell_contents else ""
                if first_cell.isdigit() and 1 <= int(first_cell) <= 31:
                    logging.info(f"  ^^^ Row {idx} appears to be for day {first_cell}")

        # Now check today's date and what row we should be reading
        today = datetime.datetime.now().date().day
        logging.info(f"\n{'=' * 80}")
        logging.info(f"TODAY'S DATE: {datetime.datetime.now().date()}")
        logging.info(f"DAY OF MONTH: {today}")
        logging.info(f"{'=' * 80}\n")

        # Show what the current logic would do
        logging.info(f"CURRENT LOGIC (buggy):")
        logging.info(f"  Would access row: {today + 1}")
        if today + 1 < len(rows):
            row = rows[today + 1]
            cells = row.xpath(".//td")
            if len(cells) > 2:
                cell_text = cells[2].text_content().strip()
                logging.info(f"  Would read day type: '{cell_text}'")

        # Try to find the correct row by looking for the day number
        logging.info(f"\nSEARCHING FOR CORRECT ROW FOR DAY {today}:")
        for idx, row in enumerate(rows):
            cells = row.xpath(".//td | .//th")
            if len(cells) > 0:
                first_cell = cells[0].text_content().strip()
                if first_cell == str(today):
                    logging.info(f"  Found day {today} at row {idx}!")
                    if len(cells) > 2:
                        day_type = cells[2].text_content().strip()
                        logging.info(f"  Day type at column 2: '{day_type}'")

        # Save the HTML for inspection
        output_file = "/logs/minagine_table_debug.html"
        with open(output_file, "w", encoding="utf-8") as f:
            f.write(driver.page_source)
        logging.info(f"\nFull HTML saved to: {output_file}")

    finally:
        if driver:
            driver.quit()


if __name__ == "__main__":
    try:
        debug_table_structure()
    except Exception as e:
        logging.error(f"Error: {e}", exc_info=True)
