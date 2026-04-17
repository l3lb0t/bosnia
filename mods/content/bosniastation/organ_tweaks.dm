/obj/item/organ/internal/brain //brain tweaks are inadvisable without the full rework, but they are separate for clarity
	relative_size = 40
	damage_reduction = -2

/obj/item/organ/internal/brain/take_damage(damage, damage_type = BRUTE, damage_flags, inflicter, armor_pen = 0, silent, do_update_health)
	. = ..()
	if (owner && damage >= 10 && _organ_damage > 75) //This probably won't be triggered by oxyloss or mercury. Probably.
		var/damage_secondary = damage * 0.20
		owner.flash_eyes()
		SET_STATUS_MAX(owner, STAT_BLURRY, damage_secondary)
		SET_STATUS_MAX(owner, STAT_CONFUSE, damage_secondary * 2)
		SET_STATUS_MAX(owner, STAT_PARA, damage_secondary)
		SET_STATUS_MAX(owner, STAT_WEAK, round(damage, 1))
		if (prob(30))
			addtimer(CALLBACK(src, PROC_REF(brain_damage_callback), damage), rand(6, 20) SECONDS, TIMER_UNIQUE)

/obj/item/organ/internal/heart
	damage_reduction = 0