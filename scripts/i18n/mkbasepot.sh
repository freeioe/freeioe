#!/bin/sh

[ -d ./scripts ] || {
	echo "Please execute as ./scripts/mkbasepot.sh" >&2
	exit 1
}

echo -n "Updating po/templates/base.pot ... "

./scripts/i18n/scan.lua web/www/ > web/www/i18n/templates/base.pot
#./scripts/i18n/scan.lua shared/ > shared/po/templates/base.pot

echo "done"
