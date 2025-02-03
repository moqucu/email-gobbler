from selenium import webdriver
import logging

driver = webdriver.Safari()
driver.get("http://www.python.org")

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

logger.info('Website title: {}'.format(driver.title))
driver.quit()