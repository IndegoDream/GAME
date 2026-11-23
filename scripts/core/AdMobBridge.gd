extends Node
## AdMobBridge (round 58): Ads.gd's way to the Poing Studios AdMob plugin
## (addons/admob, v5.1.0). Only ever loaded on a phone that has the plugin
## (Ads.pick_backend), so the web and Steam builds -- which leave addons/admob
## out -- never compile this.
##
## Order (Google's): ask for consent where the law needs it (UMP form), then
## start the SDK, then keep one break ad and one gift ad loaded. An ad is
## loaded again a little after each one closes, or after a failed load (with
## a growing wait, so a phone offline doesn't spin).

var ads                                    # Ads.gd
var cfg := {}
var started := false
var _break_ad = null                       # InterstitialAd
var _gift_ad = null                        # RewardedAd
var _break_loader = null
var _gift_loader = null
var _retry := {"break": 0.0, "gift": 0.0}
var _fails := {"break": 0, "gift": 0}
var _loading := {"break": false, "gift": false}


func setup(owner_ads, c: Dictionary) -> void:
	ads = owner_ads
	cfg = c
	process_mode = Node.PROCESS_MODE_ALWAYS
	_consent()


func _units() -> Dictionary:
	return cfg.get("units", {}).get("ios" if OS.has_feature("ios") else "android", {})


# ---- consent, then the SDK ---------------------------------------------------------------------

func _consent() -> void:
	var params := ConsentRequestParameters.new()
	params.tag_for_under_age_of_consent = false
	UserMessagingPlatform.consent_information.update(params, _consent_updated, func(_e): _init_sdk())


func _consent_updated() -> void:
	var ci = UserMessagingPlatform.consent_information
	if ci.get_is_consent_form_available() and ci.get_consent_status() == ConsentInformation.ConsentStatus.REQUIRED:
		UserMessagingPlatform.load_consent_form(func(form): form.show(func(_e): _init_sdk()), func(_e): _init_sdk())
	else:
		_init_sdk()


func _init_sdk() -> void:
	if started:
		return
	started = true
	var rc := RequestConfiguration.new()
	rc.max_ad_content_rating = str(cfg.get("max_content_rating", "T"))
	rc.tag_for_child_directed_treatment = RequestConfiguration.TagForChildDirectedTreatment.FALSE
	MobileAds.set_request_configuration(rc)
	var l := OnInitializationCompleteListener.new()
	l.on_initialization_complete = func(_status):
		_load_break()
		_load_gift()
	MobileAds.initialize(l)


func privacy_required() -> bool:
	return UserMessagingPlatform.consent_information.get_privacy_options_requirement_status() == ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED


func show_privacy() -> void:
	UserMessagingPlatform.show_privacy_options_form(func(_e): pass)


# ---- loading -------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not started:
		return
	for k in ["break", "gift"]:
		if _retry[k] > 0.0:
			_retry[k] -= delta
			if _retry[k] <= 0.0:
				if k == "break":
					_load_break()
				else:
					_load_gift()


func _failed(k: String) -> void:
	_loading[k] = false
	_fails[k] += 1
	_retry[k] = minf(30.0 * pow(2.0, float(_fails[k] - 1)), 600.0)


func _load_break() -> void:
	if _break_ad != null or _loading["break"] or str(_units().get("interstitial", "")) == "":
		return
	_loading["break"] = true
	_break_loader = InterstitialAdLoader.new()
	var cb := InterstitialAdLoadCallback.new()
	cb.on_ad_loaded = func(ad):
		_loading["break"] = false
		_fails["break"] = 0
		_break_ad = ad
		var fs := FullScreenContentCallback.new()
		fs.on_ad_dismissed_full_screen_content = func(): _closed("break")
		fs.on_ad_failed_to_show_full_screen_content = func(_e): _closed("break")
		ad.full_screen_content_callback = fs
	cb.on_ad_failed_to_load = func(_e): _failed("break")
	_break_loader.load(str(_units()["interstitial"]), AdRequest.new(), cb)


func _load_gift() -> void:
	if _gift_ad != null or _loading["gift"] or str(_units().get("rewarded", "")) == "":
		return
	_loading["gift"] = true
	_gift_loader = RewardedAdLoader.new()
	var cb := RewardedAdLoadCallback.new()
	cb.on_ad_loaded = func(ad):
		_loading["gift"] = false
		_fails["gift"] = 0
		_gift_ad = ad
		var fs := FullScreenContentCallback.new()
		fs.on_ad_dismissed_full_screen_content = func(): _closed("gift")
		fs.on_ad_failed_to_show_full_screen_content = func(_e): _closed("gift")
		ad.full_screen_content_callback = fs
	cb.on_ad_failed_to_load = func(_e): _failed("gift")
	_gift_loader.load(str(_units()["rewarded"]), AdRequest.new(), cb)


# ---- showing ------------------------------------------------------------------------------------

func ready_break() -> bool:
	return _break_ad != null


func ready_gift() -> bool:
	return _gift_ad != null


func show_break() -> void:
	if _break_ad == null:
		ads.ad_closed()
		return
	_break_ad.show()


func show_gift() -> void:
	if _gift_ad == null:
		ads.ad_closed()
		return
	var l := OnUserEarnedRewardListener.new()
	l.on_user_earned_reward = func(_item): ads.earned()
	_gift_ad.show(l)


func _closed(k: String) -> void:
	var ad = _break_ad if k == "break" else _gift_ad
	if ad:
		ad.destroy()
	if k == "break":
		_break_ad = null
	else:
		_gift_ad = null
	ads.ad_closed.call_deferred()
	_retry[k] = 2.0                         # the next one, after a breath
