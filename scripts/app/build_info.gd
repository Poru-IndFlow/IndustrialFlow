class_name BuildInfo
extends RefCounted


const PRODUCT_NAME_SETTING := "application/config/name"
const VERSION_SETTING := "application/config/version"
const BUILD_SETTING := "application/config/build"


static func get_product_name() -> String:
	return str(
		ProjectSettings.get_setting(
			PRODUCT_NAME_SETTING,
			"IndustrialFlow"
		)
	)


static func get_version() -> String:
	return str(
		ProjectSettings.get_setting(
			VERSION_SETTING,
			"0.0.0-dev"
		)
	)


static func get_build_number() -> int:
	return int(
		ProjectSettings.get_setting(
			BUILD_SETTING,
			0
		)
	)


static func get_display_string() -> String:
	return "%s %s • Build %d" % [
		get_product_name(),
		get_version(),
		get_build_number()
	]
