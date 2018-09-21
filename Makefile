CC=gcc
CFLAGS=-Wall -pedantic-errors -fconstant-cfstrings
LDFLAGS=

DEBUG=no
ifeq ($(DEBUG),yes)
CFLAGS += -g
endif

serialrenamerd:
	$(CC) $(CFLAGS) $(LDFLAGS) -framework IOKit -framework CoreFoundation -framework Foundation serialrenamerd.m -o $@

install: serialrenamerd
	@echo "Installing serialrenamer daemon for macos..."
	@cp fr.insa-rennes.clubrobot.serialrenamerd.plist /Library/LaunchDaemons/
	@cp serialrenamerd /usr/local/bin/
	@chmod 555 /usr/local/bin/serialrenamerd
	@mkdir /tmp/arduino
	@launchctl load /Library/LaunchDaemons/fr.insa-rennes.clubrobot.serialrenamerd.plist
	@echo "Done !"

remove:
	@echo "Uninstalling daemon..."
	@launchctl unload /Library/LaunchDaemons/fr.insa-rennes.clubrobot.serialrenamerd.plist
	@rm /Library/LaunchDaemons/fr.insa-rennes.clubrobot.serialrenamerd.plist
	@rm /usr/local/bin/serialrenamerd
	@rm -r /tmp/arduino
	@echo "Done !"

clean:
	@rm -f *.o *~
	@rm -f serialrenamerd
	@echo "Cleaned !"
