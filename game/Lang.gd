# game/Lang.gd — Autoload "Lang". The whole i18n: one flag, one signal, one helper.
# ─────────────────────────────────────────────────────────────────────────────
# Every piece of UI text in the game is a t(english, japanese) call; flip `jp` and
# emit `changed` and each panel re-renders itself. No translation tables, no locale
# files — there are exactly two strings per label and two languages (NFR: YAGNI).
extends Node

signal changed

var jp := false


func toggle() -> void:
	jp = not jp
	changed.emit()


func t(en: String, ja: String) -> String:
	return ja if jp else en
