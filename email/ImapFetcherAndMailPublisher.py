from abc import ABC, abstractmethod
from typing import List
import logging
import chilkat
import sys


class Email:

    def __init__(self, sent, source, to, cc, subject, body, attachments):
        self.sent = sent
        self.source = source
        self.to = to
        self.cc = cc
        self.subject = subject
        self.body = body
        self.attachments = attachments


# Define the interface contract
class ImapFetcherAndMailPublisher(ABC):
    @abstractmethod
    def fetch_emails_since(self, last_fetched_ts: float, imap_server: str, user: str, password: str) -> List[Email]:
        """Processes a payment of the given amount"""
        pass


# Concrete subclass implementing the abstract method
class ChilkatImapFetcherAndMailPublisher(ImapFetcherAndMailPublisher):
    logger = logging.getLogger(__name__)
    logging.basicConfig(level=logging.INFO)

    def fetch_emails_since(self, last_fetched_ts: float, imap_server: str, user: str, password: str) -> List[Email]:

        imap = chilkat.CkImap()

        # Connect to the iCloud IMAP Mail Server
        imap.put_Ssl(True)
        imap.put_Port(993)
        success = imap.Connect("imap.mail.me.com")
        if not success:
            self.logger.error(imap.lastErrorText())
            sys.exit(-1)

        # The username is usually the name part of your iCloud email address
        # (for example, emilyparker, not emilyparker@icloud.com).
        success = imap.Login(user, password)
        if not success:
            self.logger.error(imap.lastErrorText())
            sys.exit(-2)

        # Select an IMAP folder/mailbox
        success = imap.SelectMailbox("Inbox")
        if not success:
            self.logger.error(imap.lastErrorText())
            sys.exit(-3)

        number_messages = imap.get_NumMessages()
        self.logger.info('These many messages are waiting: {}'.format(number_messages))

        all_messages = list()

        # Convert message information into mail object
        for message_index in range(1, number_messages + 1):

            # Download the email by sequence number.
            # email is a CkEmail
            downloaded_message = imap.FetchSingle(message_index, False)
            if not imap.get_LastMethodSuccess():
                self.logger.error(imap.lastErrorText())
                sys.exit(-4)
            else:
                all_messages.append(
                    Email(
                        0.0,
                        downloaded_message.ck_from(),
                        '',
                        '',
                        downloaded_message.subject(),
                        '',
                        None
                    )
                )

        # Disconnect from the IMAP server.
        success = imap.Disconnect()
        if not success:
            self.logger.error(imap.lastErrorText())
            sys.exit(-5)

        return all_messages
