import argparse
import logging

from email.ImapFetcherAndMailPublisher import ChilkatImapFetcherAndMailPublisher

# Define the parser
commandline_parser = argparse.ArgumentParser(description='Email Fetcher')

# Declare arguments
commandline_parser.add_argument('--username', action="store", dest='username')
commandline_parser.add_argument('--password', action="store", dest='password', default='')

# Now, parse the command line arguments and store the values in the `args` variable
commandline_arguments = commandline_parser.parse_args()

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

logger.info('Username: {}'.format(commandline_arguments.username))
if commandline_arguments.password != '':
    logger.info('Password: ***')
else:
    logger.warning('No password provided!')

imap_fetcher_and_mail_publisher = ChilkatImapFetcherAndMailPublisher()
emails = imap_fetcher_and_mail_publisher.fetch_emails_since(
    0.0,
    'imap.mail.me.com',
    commandline_arguments.username,
    commandline_arguments.password
)

for email in emails:
    logger.info('From: {}'.format(email.source))
    logger.info('Subject: {}'.format(email.subject))
    logger.info('----------------------------------------------------')
