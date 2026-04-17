//first step of our evil plan is to replace most armor extensions with an ablative equivalent

/datum/extension/armor/ablative/on_blocking(damage, damage_type, damage_flags, armor_pen, blocked)
	if(!(damage_type == BRUTE || damage_type == BURN))
		return
	if(armor_degradation_coef)
		var/key = SSmaterials.get_armor_key(damage_type, damage_flags)
		var/damage_blocked = round(damage * blocked)
		if(damage_blocked)
			var/new_armor = max(0, get_value(key) - armor_degradation_coef * (damage_blocked + armor_pen))
			set_value(key, new_armor)
			var/mob/M = holder.get_recursive_loc_of_type(/mob)
			if(istype(M))
				var/list/visible = get_visible_damage()
				for(var/k in visible)
					if(LAZYACCESS(last_reported_damage, k) != visible[k])
						LAZYSET(last_reported_damage, k, visible[k])
						if (visible[k] == "completely destroyed")
							to_chat(M, SPAN_DANGER("The [k] armor on \the [holder] is [visible[k]]!"))
						else
							to_chat(M, SPAN_WARNING("The [k] armor on \the [holder] has [visible[k]] damage now!"))

/datum/extension/armor/ablative/proc/repair_damage(damage_type, arg_key)
	get_damage()
	var/list/keys
	switch (damage_type)
		if (BRUTE)
			keys = list(ARMOR_BULLET, ARMOR_BOMB, ARMOR_MELEE)
		if (BURN)
			keys = list(ARMOR_LASER, ARMOR_BOMB, ARMOR_ENERGY)
		if (TOX)
			keys = list(ARMOR_BIO)
		if (IRRADIATE)
			keys = list(ARMOR_RAD)
		if (ELECTROCUTE)
			keys = list(ARMOR_ENERGY)
	if (arg_key)
		keys = list(arg_key)
	var/success = FALSE
	for (var/key in keys)
		if (0 < max_armor_values[key] - armor_values[key])
			success = TRUE
			set_value(key, max_armor_values[key])
	return success

/datum/extension/armor/ablative/get_visible_damage()
	var/list/damages = get_damage()
	if(!LAZYLEN(damages))
		return
	var/result = list()
	for(var/key in damages)
		switch(round(100 * damages[key]/max_armor_values[key]))
			if(5 to 10)
				result[key] = "minor"
			if(11 to 25)
				result[key] = "moderate"
			if(26 to 50)
				result[key] = "serious"
			if(51 to 99)
				result[key] = "catastrophic"
			if(100)
				result[key] = "completely destroyed"
	return result

/datum/extension/armor/ablative/rig
	var/sealed = FALSE

/datum/extension/armor/ablative/rig/get_value(key)
	if(key == ARMOR_BIO && sealed)
		return 100
	return ..()

/obj/item/clothing/get_examine_strings(mob/user, distance, infix, suffix)
	. = ..()
	var/datum/extension/armor/ablative/armor_datum = get_extension(src, /datum/extension/armor)
	if(istype(armor_datum, /datum/extension/armor/ablative) && length(armor_datum.get_visible_damage()))
		. += SPAN_WARNING("It has some <a href='byond://?src=\ref[src];list_armor_damage=1'>damage</a>.")

	if(LAZYLEN(accessories))
		. += "It has the following attached: [counting_english_list(accessories)]"

	switch(ironed_state)
		if(WRINKLES_WRINKLY)
			. += "<span class='bad'>It's wrinkly.</span>"
		if(WRINKLES_NONE)
			. += "<span class='notice'>It's completely wrinkle-free!</span>"

	var/obj/item/clothing/sensor/vitals/sensor = locate() in accessories
	if(sensor)
		switch(sensor.sensor_mode)
			if(VITALS_SENSOR_OFF)
				. += "Its sensors appear to be disabled."
			if(VITALS_SENSOR_BINARY)
				. += "Its binary life sensors appear to be enabled."
			if(VITALS_SENSOR_VITAL)
				. += "Its vital tracker appears to be enabled."
			if(VITALS_SENSOR_TRACKING)
				. += "Its vital tracker and tracking beacon appear to be enabled."

#define RAG_COUNT(X) ceil((LAZYACCESS(X.matter, /decl/material/solid/organic/cloth) * 0.65) / SHEET_MATERIAL_AMOUNT)

/obj/item/clothing/get_examine_hints(mob/user, distance, infix, suffix)
	. = ..()
	var/rags = RAG_COUNT(src)
	if(rags)
		LAZYADD(., SPAN_SUBTLE("With a sharp object, you could cut \the [src] up into [rags] section\s."))

	if(length(clothing_state_modifiers))
		var/list/interactions = list()
		for(var/modifier_type in clothing_state_modifiers)
			var/decl/clothing_state_modifier/modifier = GET_DECL(modifier_type)
			interactions += modifier.name
		LAZYADD(., SPAN_SUBTLE("Use alt-click to [english_list(interactions, and_text = " or ")]."))

#undef RAG_COUNT

/obj/item/clothing/Topic(href, href_list, datum/topic_state/state)
	var/mob/user = usr
	if(istype(user))
		var/turf/T = get_turf(src)
		var/can_see = T.CanUseTopic(user, global.view_topic_state) != STATUS_CLOSE
		if(href_list["list_ungabunga"])
			if(length(accessories) && can_see)
				var/list/ties = list()
				for(var/accessory in accessories)
					ties += "[html_icon(accessory)] \a [accessory]"
				to_chat(user, "Attached to \the [src] [length(ties) == 1 ? "is" : "are"] [english_list(ties)].")
			return TOPIC_HANDLED
		if(href_list["list_armor_damage"] && can_see)
			var/datum/extension/armor/ablative/armor_datum = get_extension(src, /datum/extension/armor)
			if(istype(armor_datum))
				var/list/damages = armor_datum.get_visible_damage()
				to_chat(user, "\The [src] [html_icon(src)] has some damage:")
				for(var/key in damages)
					if (damages[key] == "completely destroyed")
						to_chat(user, "<li><b>[capitalize(damages[key])]</b> <b>[key]</b> armor.")
					else
						to_chat(user, "<li><b>[capitalize(damages[key])]</b> damage to the <b>[key]</b> armor.")
			return TOPIC_HANDLED
	. = ..()

//we also change how blocking works
/datum/extension/armor/get_blocked(damage_type, damage_flags, armor_pen = 0, damage = 5)
	var/key = SSmaterials.get_armor_key(damage_type, damage_flags)
	if(!key)
		return 0

	var/armor = get_value(key) - armor_pen
	if (damage_flags & (DAM_SHARP | DAM_LASER))
		if (armor < 0)
			return 0
		if (armor > 0)
			return 0.98
		else
			return 0.5
	armor = max(0, armor)
	if(!armor)
		return 0

	var/efficiency = min(damage / (armor_range_mult * armor), 1)
	var/coef = damage <= armor ? under_armor_mult : over_armor_mult
	return max(1 - coef * efficiency, 0)

/mob/living/human/get_thickness(obj/item/organ/external/def_zone)
	if(!def_zone)
		def_zone = ran_zone()
	if(!istype(def_zone))
		def_zone = GET_EXTERNAL_ORGAN(src, def_zone)
	if(!def_zone)
		return ..()

	. = list()
	for(var/slot in global.standard_clothing_slots)
		var/obj/item/clothing/gear = get_equipped_item(slot)
		if(!istype(gear))
			continue
		if(length(gear.accessories))
			for(var/obj/item/clothing/accessory in gear.accessories)
				if(accessory.body_parts_covered & def_zone.body_part)
					. *= accessory.agony_mod
		if(gear.body_parts_covered & def_zone.body_part)
			. *= gear.armor

/mob/living/apply_damage(damage = 0, damagetype = BRUTE, def_zone, damage_flags = 0, obj/used_weapon, armor_pen, silent = FALSE, obj/item/organ/external/given_organ)

	if(status_flags & GODMODE)
		return FALSE

	if(!damage)
		return FALSE
	var/list/before_armor = list(damage, damagetype, damage_flags)
	var/list/after_armor = modify_damage_by_armor(def_zone, damage, damagetype, damage_flags, src, armor_pen, silent)
	damage = after_armor[1]
	damagetype = after_armor[2]
	damage_flags = after_armor[3] // args modifications in case of parent calls
	if(!damage)
		return FALSE

	if (before_armor[3] & DAM_SHARP)
		var/agony_mod = get_thickness(def_zone)
		var/raw_block = before_armor[1] - after_armor[1]
		take_damage(raw_block * agony_mod, PAIN)

	switch(damagetype)
		if(BURN)
			if(has_genetic_condition(GENE_COND_COLD_RESISTANCE))
				return
			take_damage(damage, BURN, damage_flags, used_weapon, armor_pen)
		if(ELECTROCUTE)
			electrocute_act(damage, used_weapon, 1, def_zone)
		else
			take_damage(damage, damagetype, damage_flags, used_weapon, armor_pen)
	return TRUE

/mob/living/proc/get_thickness(obj/item/organ/external/def_zone)
	return 0.5

//this is just so armor datums match up

/mob/GetVoice()
	var/voice_sub
	var/obj/item/rig/rig = get_rig()
	if(rig?.speech?.voice_holder?.active && rig.speech.voice_holder.voice)
		voice_sub = rig.speech.voice_holder.voice

	if(!voice_sub)

		var/list/check_gear = list(get_equipped_item(slot_wear_mask_str), get_equipped_item(slot_head_str))
		if(rig)
			var/datum/extension/armor/ablative/rig/armor_datum = get_extension(rig, /datum/extension/armor)
			if(istype(armor_datum) && armor_datum.sealed && rig.helmet == get_equipped_item(slot_head_str))
				check_gear |= rig

		for(var/obj/item/gear in check_gear)
			if(!gear)
				continue
			var/obj/item/voice_changer/changer = locate() in gear
			if(changer && changer.active && changer.voice)
				voice_sub = changer.voice

	if(voice_sub)
		return voice_sub

	return real_name || name

//repairs
/obj/item/clothing/suit/space/proc/repair_armor(var/damtype, var/mob/user)
	var/datum/extension/armor/ablative/armor_datum = get_extension(src, /datum/extension/armor)
	if (istype(armor_datum) && armor_datum.repair_damage(damtype, null))
		user.visible_message(
			SPAN_NOTICE("\The [user] repairs the armor of \the [src]."),
			SPAN_NOTICE("You repair the armor of \the [src].")
		)

/obj/item/clothing/suit/space/attackby(obj/item/used_item, mob/user)
	if(istype(used_item,/obj/item/stack/material))
		var/repair_power = 0
		switch(used_item.get_material_type())
			if(/decl/material/solid/metal/steel)
				repair_power = 2
			if(/decl/material/solid/organic/plastic)
				repair_power = 1

		if(!repair_power)
			return FALSE

		if(ishuman(loc))
			var/mob/living/human/H = loc
			if(H.get_equipped_item(slot_wear_suit_str) == src)
				to_chat(user, SPAN_WARNING("You cannot repair \the [src] while it is being worn."))
				return TRUE

		var/obj/item/stack/P = used_item
		var/use_amt = min(P.get_amount(), 3)
		if(!use_amt || !P.use(use_amt))
			return FALSE

		repair_armor(BURN, user)

		if(burn_damage <= 0)
			to_chat(user, "There is no surface damage on \the [src] to repair.") //maybe change the descriptor to more obvious? idk what
			return TRUE

		repair_breaches(BURN, use_amt * repair_power, user)
		return TRUE

	else if(IS_WELDER(used_item))

		if(ishuman(loc))
			var/mob/living/human/H = loc
			if(H.get_equipped_item(slot_wear_suit_str) == src)
				to_chat(user, SPAN_WARNING("You cannot repair \the [src] while it is being worn."))
				return TRUE

		var/obj/item/weldingtool/welder = used_item
		if(!welder.weld(5))
			to_chat(user, SPAN_WARNING("You need more welding fuel to repair this suit."))
			return TRUE

		repair_armor(BRUTE, user)

		if (brute_damage <= 0)
			to_chat(user, "There is no structural damage on \the [src] to repair.")
			return TRUE

		repair_breaches(BRUTE, 3, user)
		return TRUE

	else if(istype(used_item, /obj/item/stack/tape_roll/duct_tape))
		var/datum/breach/target_breach		//Target the largest unpatched breach.
		for(var/datum/breach/B in breaches)
			if(B.patched)
				continue
			if(!target_breach || (B.class > target_breach.class))
				target_breach = B

		if(!target_breach)
			to_chat(user, "There are no open breaches to seal with \the [used_item].")
		else
			var/obj/item/stack/tape_roll/duct_tape/D = used_item
			var/amount_needed = ceil(target_breach.class * 2)
			if(!D.can_use(amount_needed))
				to_chat(user, SPAN_WARNING("There's not enough [D.plural_name] in your [src] to seal \the [target_breach.descriptor] on \the [src]! You need at least [amount_needed] [D.plural_name]."))
				return TRUE

			if(do_after(user, user.get_equipped_item(slot_wear_suit_str) == src? 6 SECONDS : 3 SECONDS, isliving(loc)? loc : null)) //Sealing a breach on your own suit is awkward and time consuming
				D.use(amount_needed)
				playsound(src, 'sound/effects/tape.ogg',25)
				user.visible_message(
					SPAN_NOTICE("\The [user] uses some [D.plural_name] to seal \the [target_breach.descriptor] on \the [src]."),
					SPAN_NOTICE("You use [amount_needed] [D.plural_name] of \the [used_item] to seal \the [target_breach.descriptor] on \the [src].")
				)
				target_breach.patched = TRUE
				target_breach.update_descriptor()
				calc_breach_damage()
		return TRUE
	return ..()

//now we change clothing to match

/obj/item/rig
	armor_type = /datum/extension/armor/ablative/rig
	armor_degradation_speed = 0.075
	var/agony_mod = 0.75

/obj/item/rig/light
	agony_mod = 1

/obj/item/rig/merc/heavy
	agony_mod = 0.5

/obj/item/clothing
	armor_type = /datum/extension/armor/ablative
	armor_degradation_speed = 0.1
	var/agony_mod = 0.9

/obj/item/clothing/suit/armor/bulletproof
	agony_mod = 0.75

/obj/item/clothing/suit/armor/riot
	agony_mod = 0.5

/obj/item/clothing/shoes/legguards/riot
	agony_mod = 0.5

/obj/item/clothing/gloves/armguards/riot
	agony_mod = 0.5

/obj/item/clothing/suit/bomb_suit
	agony_mod = 0.75

/obj/item/clothing/suit/armor/forged
	armor_degradation_speed = 0.2

/obj/item/clothing/suit/armor/crafted
	armor_degradation_speed = 0.2

/obj/item/clothing/armor_attachment/plate
	armor_degradation_speed = 0.3
	agony_mod = 1

/obj/item/clothing/head/helmet/riot
	agony_mod = 0.5