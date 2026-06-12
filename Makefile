PREFIX ?= /usr/local

install:
	install -Dm755 bin/omarchy-kali-vm -t $(DESTDIR)$(PREFIX)/bin/
	install -Dm755 bin/omarchy-kali-vm-integrate-os -t $(DESTDIR)$(PREFIX)/bin/
	install -Dm755 bin/omarchy-kali-vm-unintegrate-os -t $(DESTDIR)$(PREFIX)/bin/
	install -Dm644 share/omarchy-menu.sh -t $(DESTDIR)$(PREFIX)/share/omarchy-kali-vm/
	install -Dm644 share/hypr/omarchy-kali-vm.conf -t $(DESTDIR)$(PREFIX)/share/omarchy-kali-vm/hypr/
	install -Dm644 assets/icons/kali.png $(DESTDIR)$(PREFIX)/share/icons/hicolor/256x256/apps/omarchy-kali-vm.png
	install -Dm644 lib/config.sh -t $(DESTDIR)$(PREFIX)/share/omarchy-kali-vm/lib/
	install -Dm644 lib/debug.sh -t $(DESTDIR)$(PREFIX)/share/omarchy-kali-vm/lib/
	install -Dm644 lib/state.sh -t $(DESTDIR)$(PREFIX)/share/omarchy-kali-vm/lib/
	install -Dm644 lib/ui.sh -t $(DESTDIR)$(PREFIX)/share/omarchy-kali-vm/lib/
	install -Dm644 lib/docker.sh -t $(DESTDIR)$(PREFIX)/share/omarchy-kali-vm/lib/
	install -Dm644 lib/download.sh -t $(DESTDIR)$(PREFIX)/share/omarchy-kali-vm/lib/
	install -Dm644 lib/patch.sh -t $(DESTDIR)$(PREFIX)/share/omarchy-kali-vm/lib/
	install -Dm644 lib/lifecycle.sh -t $(DESTDIR)$(PREFIX)/share/omarchy-kali-vm/lib/

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/omarchy-kali-vm
	rm -f $(DESTDIR)$(PREFIX)/bin/omarchy-kali-vm-integrate-os
	rm -f $(DESTDIR)$(PREFIX)/bin/omarchy-kali-vm-unintegrate-os
	rm -rf $(DESTDIR)$(PREFIX)/share/omarchy-kali-vm/
	rm -f $(DESTDIR)$(PREFIX)/share/icons/hicolor/256x256/apps/omarchy-kali-vm.png
