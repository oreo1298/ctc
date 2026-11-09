# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
class_name I18n
extends RefCounted
## Translation helpers for code that cannot call tr() (static functions).


## Marks a message for the translation catalogue without translating it
## (gettext's N_()). The UI that shows it passes it through tr().
static func tr_noop(msg: String) -> String:
	return msg
