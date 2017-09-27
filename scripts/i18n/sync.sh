#!/bin/sh

mkdir -p www/i18n/template

./scripts/i18n/scan.lua "www" > "www/i18n/template/web.pot"
./scripts/i18n/update.lua "/www/i18n"

for f in `ls apps`; do
	echo "Process -> $f"

	if [ -d "apps/$f/i18n" ]; then
		mkdir -p apps/$f/i18n/template

		#./scripts/i18n/scan.lua "$f" > "apps/$f/i18n/template/all.pot"
		./scripts/i18n/scan.lua "apps/$f" > "apps/$f/i18n/template/web.pot"
		./scripts/i18n/update.lua "apps/$f/i18n"
	fi
done

