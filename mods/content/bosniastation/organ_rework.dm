//we separate this horror from the rest of organ stuff as it is almost entirely one line changes in massive blocks of code but also kind of has to be a mod

#define DAM_ARTERY 128 // Massively reduces chance of organ damage, while increasing chance of severing an artery

/decl/grab/normal/attack_throat(var/obj/item/grab/grab, var/obj/item/used_item, mob/user)
	var/mob/living/affecting = grab.get_affecting_mob()
	if(!affecting)
		return
	if(!user.check_intent(I_FLAG_HARM))
		return 0 // Not trying to hurt them.

	if(!used_item.has_edge() || !used_item.get_attack_force(user) || used_item.atom_damage_type != BRUTE)
		return 0 //unsuitable weapon
	user.visible_message("<span class='danger'>\The [user] begins to slit [affecting]'s throat with \the [used_item]!</span>")

	user.next_move = world.time + 20 //also should prevent user from triggering this repeatedly
	if(!do_after(user, 20*user.skill_delay_mult(SKILL_COMBAT) , progress = 0))
		return 0
	if(!(grab && grab.affecting == affecting)) //check that we still have a grab
		return 0

	var/damage_mod = 1
	var/damage_flags = used_item.damage_flags() | DAM_ARTERY
	//presumably, if they are wearing a helmet that stops pressure effects, then it probably covers the throat as well
	var/force = used_item.expend_attack_force(user)
	var/obj/item/clothing/head/helmet = affecting.get_equipped_item(slot_head_str)
	if(istype(helmet) && (helmet.body_parts_covered & SLOT_HEAD) && (helmet.item_flags & ITEM_FLAG_AIRTIGHT) && !isnull(helmet.max_pressure_protection))
		var/datum/extension/armor/armor_datum = get_extension(helmet, /datum/extension/armor)
		if(armor_datum)
			damage_mod -= armor_datum.get_blocked(BRUTE, damage_flags, used_item.armor_penetration, force*1.5)

	var/total_damage = 0
	for(var/i in 1 to 3)
		var/damage = min(force*1.5, 20)*damage_mod
		affecting.apply_damage(damage, used_item.atom_damage_type, BP_HEAD, damage_flags, armor_pen = 100, used_weapon=used_item)
		total_damage += damage

	if(total_damage)
		user.visible_message("<span class='danger'>\The [user] slit [affecting]'s throat open with \the [used_item]!</span>")

		if(used_item.hitsound)
			playsound(affecting.loc, used_item.hitsound, 50, 1, -1)

	grab.last_action = world.time

	admin_attack_log(user, affecting, "Knifed their victim", "Was knifed", "knifed")
	return 1

/obj/item/organ/external/take_damage(damage, damage_type = BRUTE, damage_flags, inflicter, armor_pen = 0, silent, do_update_health, override_droplimb)

	if(!owner)
		return ..()

	var/final_brute_mod = get_brute_mod(damage_flags) + (0.2 * burn_dam/max_damage) // extra brute taken if you have burn damage. why? ask whoever originally coded it.
	var/final_burn_mod = get_burn_mod(damage_flags)

	var/brute = damage_type == BRUTE ? round(damage * final_brute_mod, 0.1) : 0
	var/burn  = damage_type == BURN  ? round(damage * final_burn_mod,  0.1) : 0

	if((brute <= 0) && (burn <= 0))
		return 0

	var/sharp = (damage_flags & DAM_SHARP)
	var/edge  = (damage_flags & DAM_EDGE)
	var/laser = (damage_flags & DAM_LASER)
	var/blunt = !!(brute && !sharp && !edge)

	// Handle some status-based damage multipliers.
	if(BP_IS_CRYSTAL(src) && burn && laser)
		brute += burn // Stress fracturing from heat!
		owner.bodytemperature += burn
		burn = 0
		if(prob(25))
			owner.visible_message(SPAN_WARNING("\The [owner]'s crystalline [name] shines with absorbed energy!"))

	if(inflicter)
		add_autopsy_data(inflicter, brute + burn)

	var/spillover = 0
	var/pure_brute = brute
	if(!is_damageable(brute + burn))
		spillover =  brute_dam + burn_dam + brute - max_damage
		if(spillover > 0)
			brute = max(brute - spillover, 0)
		else
			spillover = brute_dam + burn_dam + brute + burn - max_damage
			if(spillover > 0)
				burn = max(burn - spillover, 0)

	//If limb took enough damage, try to cut or tear it off
	if(owner && loc == owner)
		owner.update_health() //droplimb will call update_health() again if it does end up being called
		if((limb_flags & ORGAN_FLAG_CAN_AMPUTATE) && get_config_value(/decl/config/toggle/on/health_limbs_can_break))
			var/total_damage = brute_dam + burn_dam + brute + burn + spillover
			var/threshold = max_damage * get_config_value(/decl/config/num/health_organ_health_multiplier)
			if(total_damage > threshold)
				if(attempt_dismemberment(pure_brute, burn, sharp, edge, inflicter, spillover, total_damage > threshold*6, override_droplimb = override_droplimb))
					return

	//blunt damage is gud at fracturing
	if(brute_dam + brute > min_broken_damage && prob(brute_dam + brute * (1+blunt)) )
		fracture()

	// High brute damage or sharp objects may damage internal organs
	if(LAZYLEN(internal_organs) && damage_internal_organs(brute, burn, damage_flags))
		brute /= 2
		burn  /= 2

	if((status & ORGAN_BROKEN) && brute)
		jostle_bone(brute)
		if(can_feel_pain() && prob(40))
			owner.emote(/decl/emote/audible/scream)	//getting hit on broken hand hurts

	// If the limbs can break, make sure we don't exceed the maximum damage a limb can take before breaking
	var/datum/wound/created_wound
	var/block_cut = (species.species_flags & SPECIES_FLAG_NO_MINOR_CUT) && brute <= 15
	var/can_cut = !block_cut && !BP_IS_PROSTHETIC(src) && (sharp || prob(brute))

	if(brute)
		var/to_create = BRUISE
		if(can_cut)
			to_create = CUT
			//need to check sharp again here so that blunt damage that was strong enough to break skin doesn't give puncture wounds
			if(sharp && !edge)
				to_create = PIERCE
		var/arterial = damage_flags & DAM_ARTERY
		created_wound = createwound(to_create, brute, arterial)

	if(burn)
		if(laser)
			created_wound = createwound(LASER, burn)
			if(prob(40))
				owner.ignite_fire()
		else
			created_wound = createwound(BURN, burn)

	//Initial pain spike
	add_pain(0.6*burn + 0.4*brute)

	//Disturb treated burns
	if(brute > 5)
		var/disturbed = 0
		for(var/datum/wound/burn/wound in wounds)
			if((wound.disinfected || wound.salved) && prob(brute + wound.damage))
				wound.disinfected = 0
				wound.salved = 0
				disturbed += wound.damage
		if(disturbed)
			to_chat(owner,"<span class='warning'>Ow! Your burns were disturbed.</span>")
			add_pain(0.5*disturbed)

	//If there are still hurties to dispense
	if (spillover)
		owner.shock_stage += spillover * get_config_value(/decl/config/num/health_organ_damage_spillover_multiplier)

	// sync the organ's damage with its wounds
	update_damages()
	if(do_update_health)
		owner.update_health()
	if(status & ORGAN_BLEEDING)
		owner.update_bandages()

	if(owner && update_damstate())
		owner.update_damage_overlays()

	if(created_wound && isobj(inflicter))
		var/obj/O = inflicter
		O.after_wounding(src, created_wound)

	return created_wound

/obj/item/organ/external/createwound(var/type = CUT, var/damage, var/surgical, var/arterial = FALSE)

	if(!owner || damage <= 0)
		return

	if(BP_IS_CRYSTAL(src))
		type = SHATTER
		if(damage >= 15 || prob(1))
			playsound(loc, 'sound/effects/hit_on_shattered_glass.ogg', 40, 1) // Crash!
	else if((limb_flags & ORGAN_FLAG_SKELETAL) || (BP_IS_PROSTHETIC(src) && !bodytype.is_robotic))
		if(type == BURN)
			type = CHARRED
		else
			type = SHATTER

	//moved these before the open_wound check so that having many small wounds for example doesn't somehow protect you from taking internal damage (because of the return)
	//Brute damage can possibly trigger an internal wound, too.
	var/local_damage = brute_dam + burn_dam + damage
	if(!surgical && (type in list(CUT, PIERCE, BRUISE)) && damage > 15 && local_damage > 30)

		var/internal_damage
		if(prob(damage + (arterial)*50) && sever_artery())
			internal_damage = TRUE
		if(prob(ceil(damage/4)) && sever_tendon())
			internal_damage = TRUE
		if(internal_damage)
			owner.custom_pain("You feel something rip in your [name]!", 50, affecting = src)

	//Burn damage can cause fluid loss due to blistering and cook-off
	if((type in list(BURN, LASER)) && (damage > 5 || damage + burn_dam >= 15) && !BP_IS_PROSTHETIC(src))
		var/fluid_loss_severity
		switch(type)
			if(BURN)  fluid_loss_severity = FLUIDLOSS_WIDE_BURN
			if(LASER) fluid_loss_severity = FLUIDLOSS_CONC_BURN
		var/fluid_loss = (damage/(owner.get_max_health() - get_config_value(/decl/config/num/health_health_threshold_dead))) * SPECIES_BLOOD_DEFAULT * fluid_loss_severity
		owner.remove_blood(fluid_loss)

	// first check whether we can widen an existing wound
	if(!surgical && LAZYLEN(wounds) && prob(max(50+(number_wounds-1)*10,90)))
		if((type == CUT || type == BRUISE) && damage >= 5)
			//we need to make sure that the wound we are going to worsen is compatible with the type of damage...
			var/list/compatible_wounds = list()
			for (var/datum/wound/wound in wounds)
				if (wound.can_worsen(type, damage))
					compatible_wounds += wound

			if(compatible_wounds.len)
				var/datum/wound/wound = pick(compatible_wounds)
				wound.open_wound(damage)
				if(owner && prob(25))
					if(BP_IS_CRYSTAL(src))
						owner.visible_message(SPAN_DANGER("The cracks in \the [owner]'s [name] spread."),\
						SPAN_DANGER("The cracks in your [name] spread."),\
						SPAN_DANGER("You hear the cracking of crystal."))
					else if(BP_IS_PROSTHETIC(src))
						owner.visible_message(SPAN_DANGER("The damage to \the [owner]'s [name] worsens."),\
						SPAN_DANGER("The damage to your [name] worsens."),\
						SPAN_DANGER("You hear the screech of abused metal."))
					else
						owner.visible_message(SPAN_DANGER("The wound on \the [owner]'s [name] widens with a nasty ripping noise."),\
						SPAN_DANGER("The wound on your [name] widens with a nasty ripping noise."),\
						SPAN_DANGER("You hear a nasty ripping noise, as if flesh is being torn apart."))
				return wound

	//Creating wound
	var/wound_type = get_wound_type(type, damage)

	if(wound_type)
		var/datum/wound/wound = new wound_type(damage, src, surgical)

		//Check whether we can add the wound to an existing wound
		if(surgical)
			wound.autoheal_cutoff = 0
		else
			for(var/datum/wound/other in wounds)
				if(other.can_merge_wounds(wound))
					other.merge_wound(wound)
					return other
		LAZYADD(wounds, wound)
		return wound

/obj/item/organ/external/damage_internal_organs(brute, burn, damage_flags)
	if(!LAZYLEN(internal_organs))
		return FALSE

	var/laser = (damage_flags & DAM_LASER)
	var/sharp = (damage_flags & DAM_SHARP)

	var/damage_amt = brute
	var/cur_damage = brute_dam
	if(laser || BP_IS_PROSTHETIC(src))
		damage_amt += burn
		cur_damage += burn_dam

	if(!damage_amt)
		return FALSE

	var/organ_damage_threshold = 10
	if(sharp || organ_tag == BP_HEAD)
		organ_damage_threshold *= 0.5
	if(laser)
		organ_damage_threshold *= 2
	var/arterial = damage_flags & DAM_ARTERY
	if(!(cur_damage + damage_amt >= max_damage) && !(damage_amt >= organ_damage_threshold + arterial * 50))
		return FALSE
	var/success = FALSE
	var/list/victims = list()
	for(var/obj/item/organ/internal/organ in internal_organs)
		if(organ.get_organ_damage() < organ.max_damage)
			victims[organ] = min(organ.relative_size + 3 * damage_amt/organ_damage_threshold, 100)
			var/organ_chance = victims[organ]
			if (!sharp)
				organ_chance = min(100, organ_chance*1.5)

			if(prob(organ_chance))
				var/local_damage_reduction = 0
				if(encased && !(status & ORGAN_BROKEN)) //ribs protect
					local_damage_reduction += 0.35
					if (damage_flags & DAM_SHARP)
						local_damage_reduction += 0.25
				damage_amt -= damage_amt*organ.damage_reduction
				damage_amt -= damage_amt*local_damage_reduction
				damage_amt = max(damage_amt, 0)
				organ.take_damage(damage_amt)
				success = TRUE
	return success

/obj/item/gun/play_fire_sound(atom/movable/firer, obj/item/projectile/P)
	var/shot_sound = fire_sound
	var/shot_sound_vol = 50
	if((istype(P) && P.fire_sound))
		shot_sound = P.fire_sound
		shot_sound_vol = P.fire_sound_vol
	if(silencer)
		shot_sound_vol = P.fire_sound_vol_silenced

	playsound(firer, shot_sound, shot_sound_vol, 1)

//Suicide handling.

/obj/item/gun/handle_suicide(mob/living/user)
	if(!ishuman(user))
		return
	var/mob/living/human/M = user

	mouthshoot = 1
	admin_attacker_log(user, "is attempting to suicide with \a [src]")
	M.visible_message("<span class='danger'>[user] sticks their gun in their mouth, ready to pull the trigger...</span>")
	if(!do_after(user, 40, progress=0))
		M.visible_message(SPAN_NOTICE("[user] decided life was worth living."))
		mouthshoot = 0
		return

	if(safety())
		user.visible_message("*click click*", SPAN_DANGER("*click*"))
		playsound(src.loc, 'sound/weapons/empty.ogg', 100, 1)
		mouthshoot = 0
		return

	var/obj/item/projectile/in_chamber = consume_next_projectile()
	if (istype(in_chamber))
		user.visible_message("<span class = 'warning'>[user] pulls the trigger.</span>")
		var/shot_sound = in_chamber.fire_sound? in_chamber.fire_sound : fire_sound
		if(silencer)
			playsound(user, shot_sound, 10, 1)
		else
			playsound(user, shot_sound, 50, 1)
		if(istype(in_chamber, /obj/item/projectile/beam/lastertag))
			user.show_message("<span class = 'warning'>You feel rather silly, trying to commit suicide with a toy.</span>")
			mouthshoot = 0
			return

		in_chamber.on_hit(M)
		if (in_chamber.atom_damage_type != PAIN)
			log_and_message_admins("[key_name(user)] commited suicide using \a [src]")
			var/shot_damage = in_chamber.damage
			if (istype (in_chamber, /obj/item/projectile/bullet/pellet)) //handle buckshot
				var/obj/item/projectile/bullet/pellet/shell = in_chamber
				shot_damage = shell.pellets*shell.damage
			user.apply_damage(shot_damage, in_chamber.atom_damage_type, BP_HEAD, in_chamber.damage_flags(), used_weapon = "Point blank shot in the mouth with \a [in_chamber]")
			user.death()
		else
			to_chat(user, "<span class = 'notice'>Ow...</span>")
			user.apply_effect(110,PAIN,0)
		qdel(in_chamber)
		mouthshoot = 0
		return
	else
		handle_click_empty(user)
		mouthshoot = 0
		return
