package pet.buddy

import android.speech.tts.Voice

/**
 * Google's voices are named like "en-us-x-iol-network". Buddy gives each speaker a first name, so you can pick one you like.
 * ponytail: names are ours, not Google's; a speaker missing here shows as "Voice <code>". Listen before you pick.
 */
object Voices {
    private val names = mapOf(
        "en-us-x-iob" to "Ava", "en-us-x-iog" to "Ella", "en-us-x-iol" to "Leo", "en-us-x-iom" to "Max",
        "en-us-x-sfg" to "Sofia", "en-us-x-tpc" to "Clara", "en-us-x-tpd" to "Dan", "en-us-x-tpf" to "Fiona",
        "en-gb-x-gba" to "Amelia", "en-gb-x-gbb" to "Oliver", "en-gb-x-gbc" to "Grace", "en-gb-x-gbd" to "Harry",
        "en-gb-x-gbg" to "Isla", "en-gb-x-rjs" to "James",
        "en-in-x-ena" to "Ananya", "en-in-x-enc" to "Priya", "en-in-x-end" to "Arjun", "en-in-x-ene" to "Rohan",
        "en-in-x-ahp" to "Meera", "en-in-x-cxx" to "Kabir",
        "en-au-x-aua" to "Ruby", "en-au-x-aub" to "Jack", "en-au-x-auc" to "Matilda", "en-au-x-aud" to "Noah",
    )
    private val accents = mapOf("US" to "American", "GB" to "British", "IN" to "Indian", "AU" to "Australian", "NG" to "Nigerian")

    /** "en-us-x-iol-network" → "en-us-x-iol" (the same speaker, online or offline). Null for Google's unnamed default voices. */
    fun speaker(v: Voice): String? = Regex("^([a-z]{2}-[a-z]{2}-x-[a-z]{3})").find(v.name)?.groupValues?.get(1)

    fun name(v: Voice): String = speaker(v)?.let { names[it] ?: "Voice ${it.takeLast(3).uppercase()}" } ?: v.name

    /** "Leo · American · natural" */
    fun label(v: Voice): String = name(v) + " · " + (accents[v.locale.country] ?: v.locale.displayCountry) +
        if (v.isNetworkConnectionRequired) " · natural" else " · offline"
}
