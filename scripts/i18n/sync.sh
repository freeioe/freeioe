#!/bin/sh

for f in `ls apps`; do
	echo "Process -> $f"

	if [ -d "apps/$f/web/i18n" ]; then
		mkdir -p apps/$f/web/i18n/templates

		#./scripts/i18n/scan.lua "$f" > "apps/$f/web/i18n/templates/all.pot"
		./scripts/i18n/scan.lua "apps/$f/web" > "apps/$f/web/i18n/templates/web.pot"
		./scripts/i18n/update.lua "apps/$f/web/i18n"
	fi
done

./scripts/i18n/mkbasepot.sh
./scripts/i18n/update.lua web/www/i18n
