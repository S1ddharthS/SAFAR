"""Localized response templates for the grounded assistant (F22).

Every answer the assistant gives is assembled from SAFAR's own records through
these templates. The catalogue is deliberately small and auditable: there is no
model call, no vendor, and no message text leaves the process. When a key is
missing in a language the English string is used so an answer is never blank.
"""

SUPPORTED = ("en", "es", "fr", "de", "pt", "it", "hi", "ja")

TEXTS: dict[str, dict[str, str]] = {
    "en": {
        "general.capabilities": (
            "I can answer from this trip's confirmed itinerary, expenses, members, open "
            "proposals and recommendation batches, or look up a catalog activity by name. "
            "No external AI model is configured, so I only state what SAFAR actually has."
        ),
        "general.no_trip": (
            "Choose a trip workspace and ask about its itinerary, budget, members, open "
            "proposals or recommendations. I only state what SAFAR has recorded."
        ),
        "general.unknown": (
            "I did not find that in this trip's records. I can help with the itinerary, "
            "budget, members, open proposals, recommendations, catalog activities and "
            "weather when a provider is configured."
        ),
        "overview.heading": "Here is what SAFAR has recorded for {name}.",
        "overview.facts": (
            "Destination {destination}. Dates {start} to {end}, {nights} nights. "
            "Group size {group_size}. Currency {currency}."
        ),
        "overview.itinerary": (
            "{confirmed} confirmed itinerary item(s) across {days} day(s); {protected} "
            "marked as protected time."
        ),
        "overview.budget": (
            "Trip budget {currency} {budget}. Tracked spending {currency} {spent}."
        ),
        "overview.no_budget": "No trip budget is set, so I won't estimate one.",
        "overview.limit": "Dates, budgets and costs are trip records, not live prices.",
        "weather.unavailable": (
            "I don't have a weather provider configured, so I can't tell you the forecast. "
            "I won't invent one. If conditions change, open Trip Rescue and it can propose "
            "indoor replacements for the group to approve."
        ),
        "weather.forecast": (
            "Forecast for {place} from {provider}: {summary}. This is a prediction, not an "
            "observation."
        ),
        "weather.day": "{date}: {label}, {min_temp}–{max_temp} °C, rain chance {rain}%.",
        "weather.limit": (
            "Weather is predicted by Open-Meteo from rounded coordinates. It can be wrong "
            "and is not a safety guarantee."
        ),
        "weather.no_location": (
            "This trip has no destination coordinates, so I can't request a forecast."
        ),
        "itinerary.empty": (
            "There are no confirmed itinerary items yet. Add an activity, or run the Group "
            "Experience Engine and let the group approve a suggestion."
        ),
        "itinerary.plan": "On {day} the confirmed plan is: {listing}.",
        "itinerary.item": "{time} {title}",
        "itinerary.item_cost": "{time} {title} (~{currency} {cost})",
        "itinerary.limit": (
            "These are confirmed plan entries. Travel durations are estimates, not live "
            "traffic."
        ),
        "itinerary.next_day": "The next day with confirmed items is {day}.",
        "budget.total": "Tracked group spending is {currency} {total}.",
        "budget.mine_ahead": (
            "Your net position is {net} — the group currently owes you your share."
        ),
        "budget.mine_behind": (
            "Your net position is {net} — you currently owe the group your share."
        ),
        "budget.settlement": (
            "Suggested next settlement: {from_name} pays {to_name} {currency} {amount}."
        ),
        "budget.track_only": "SAFAR tracks and calculates only; it does not move money.",
        "budget.limit": (
            "Balances reflect expenses entered in SAFAR, not external payments."
        ),
        "budget.plan": "The trip budget is {currency} {budget}.",
        "recommend.empty": (
            "I don't have a recommendation batch for this trip yet. Open the Group "
            "Experience Engine and choose Everyone Wins, Your Turn, or Surprise Us."
        ),
        "recommend.batch": "The latest {mode} batch suggests: {listing}.",
        "recommend.rec": "{name} (score {score}, minimum member fit {fit})",
        "recommend.none_stored": "The latest batch has no stored recommendations.",
        "recommend.limit": (
            "Scores are model outputs based on available trip data; review the "
            "explanations before approving."
        ),
        "recommend.proposals": (
            "These are proposals, not confirmed changes. The group decides before the "
            "plan changes."
        ),
        "vote.none": "There are no open proposals waiting for a decision.",
        "vote.open": (
            "{count} proposal(s) are open: {titles}. The engine recommends; the group "
            "decides."
        ),
        "members.names": "{count} active member(s): {names}.",
        "members.limit": "Private budgets and preferences are intentionally not shown.",
        "privacy.answer": (
            "Trips and memories are private by default. Location sharing is optional and "
            "time-limited. You can withdraw consent, export your data, or delete your "
            "account from Settings. Traveller meetups require mutual acceptance, and "
            "identity checks do not guarantee safety."
        ),
        "place.summary": (
            "{name} — catalog estimate {currency} {price} per person, about {minutes} "
            "minutes, effort {effort} of 5."
        ),
        "place.hours_recorded": (
            "Recorded opening hours: {hours}. This is catalog data, not a live feed."
        ),
        "place.hours_missing": (
            "Opening hours are not recorded, so I can't confirm them."
        ),
        "place.stepfree": "Step-free access is recorded in the catalog.",
        "place.access_unknown": (
            "Wheelchair accessibility is unknown; I won't assume it."
        ),
        "place.access_barriers": (
            "The catalog records accessibility barriers for this activity."
        ),
        "place.reports_signal": (
            "Latest traveller signal: {category} — {source}, freshness {freshness}."
        ),
        "place.reports_none": (
            "There are no recent traveller reports for this place."
        ),
        "place.limit_availability": (
            "No live availability, ticket or queue API is configured."
        ),
        "place.limit_catalog": (
            "Prices and hours come from the catalog record and may be out of date."
        ),
        "clarify.ask": (
            "Which day or activity do you mean? I ask rather than guess because the "
            "itinerary can change during the trip."
        ),
        "language.note_mixed": (
            "Your message mixed {mixed} with {language}. I answered in the language I am "
            "most confident about; ask again in either language if you prefer."
        ),
        "language.note_unsupported": (
            "I detected {script}, which I can't answer in yet. Replies are available in "
            "English, Spanish, French, German, Portuguese, Italian, Hindi and Japanese, "
            "so this answer is in {language}."
        ),
        "language.note_unknown": (
            "I could not identify the language confidently, so I answered in {language}. "
            "You can pick a language explicitly."
        ),
        "language.limit": (
            "This is a template answer generated locally from SAFAR's records, not a "
            "human or model translation."
        ),
        "action.itinerary": "Open itinerary",
        "action.engine": "Open the Group Engine",
        "action.expenses": "Open expenses",
        "action.members": "Open members",
        "action.voting": "Open voting",
        "action.privacy": "Open privacy settings",
        "action.rescue": "Open Trip Rescue",
        "action.evidence": "Open the Decision Evidence Passport",
        "action.overview": "Open trip overview",
        "action.review": "Review recommendations",
        "action.open_trip": "Open a trip",
        "limit.no_llm": "No external LLM or live travel API is configured.",
        "limit.trip_data": "This answer uses only SAFAR trip records.",
        "role.owner": "owner",
        "role.admin": "admin",
        "role.member": "member",
        "role.guest": "guest",
    },
    "es": {
        "general.capabilities": (
            "Puedo responder con el itinerario confirmado, los gastos, los miembros, las "
            "propuestas abiertas y los lotes de recomendaciones de este viaje, o buscar "
            "una actividad del catálogo por nombre. No hay un modelo de IA externo "
            "configurado, así que solo digo lo que SAFAR tiene registrado."
        ),
        "general.no_trip": (
            "Elige un espacio de viaje y pregunta por su itinerario, presupuesto, "
            "miembros, propuestas abiertas o recomendaciones. Solo digo lo que SAFAR ha "
            "registrado."
        ),
        "general.unknown": (
            "No encontré eso en los registros de este viaje. Puedo ayudar con el "
            "itinerario, el presupuesto, los miembros, las propuestas abiertas, las "
            "recomendaciones, las actividades del catálogo y el tiempo cuando hay un "
            "proveedor configurado."
        ),
        "overview.heading": "Esto es lo que SAFAR ha registrado para {name}.",
        "overview.facts": (
            "Destino {destination}. Fechas del {start} al {end}, {nights} noches. "
            "Grupo de {group_size}. Moneda {currency}."
        ),
        "overview.itinerary": (
            "{confirmed} elemento(s) confirmado(s) en {days} día(s); {protected} marcados "
            "como tiempo protegido."
        ),
        "overview.budget": (
            "Presupuesto del viaje {currency} {budget}. Gasto registrado {currency} {spent}."
        ),
        "overview.no_budget": (
            "No hay presupuesto de viaje definido, así que no lo voy a estimar."
        ),
        "overview.limit": (
            "Las fechas, los presupuestos y los costes son registros del viaje, no "
            "precios en vivo."
        ),
        "weather.unavailable": (
            "No tengo un proveedor de meteorología configurado, así que no puedo darte el "
            "pronóstico. No lo voy a inventar. Si el tiempo cambia, abre Trip Rescue y "
            "puede proponer alternativas bajo techo para que el grupo las apruebe."
        ),
        "weather.forecast": (
            "Pronóstico para {place} de {provider}: {summary}. Es una predicción, no una "
            "observación."
        ),
        "weather.day": (
            "{date}: {label}, {min_temp}–{max_temp} °C, probabilidad de lluvia {rain}%."
        ),
        "weather.limit": (
            "Open-Meteo predice el tiempo a partir de coordenadas redondeadas. Puede "
            "fallar y no es una garantía de seguridad."
        ),
        "weather.no_location": (
            "Este viaje no tiene coordenadas de destino, así que no puedo pedir un "
            "pronóstico."
        ),
        "itinerary.empty": (
            "Todavía no hay elementos confirmados en el itinerario. Añade una actividad o "
            "ejecuta el Motor de Experiencia de Grupo y deja que el grupo apruebe una "
            "sugerencia."
        ),
        "itinerary.plan": "El {day} el plan confirmado es: {listing}.",
        "itinerary.item": "{time} {title}",
        "itinerary.item_cost": "{time} {title} (~{currency} {cost})",
        "itinerary.limit": (
            "Son entradas confirmadas del plan. Las duraciones de desplazamiento son "
            "estimaciones, no tráfico en vivo."
        ),
        "itinerary.next_day": "El próximo día con elementos confirmados es el {day}.",
        "budget.total": "El gasto grupal registrado es {currency} {total}.",
        "budget.mine_ahead": (
            "Tu posición neta es {net}: el grupo te debe tu parte por ahora."
        ),
        "budget.mine_behind": (
            "Tu posición neta es {net}: por ahora debes tu parte al grupo."
        ),
        "budget.settlement": (
            "Próxima liquidación sugerida: {from_name} paga {to_name} {currency} {amount}."
        ),
        "budget.track_only": (
            "SAFAR solo registra y calcula; no mueve dinero."
        ),
        "budget.limit": (
            "Los saldos reflejan los gastos introducidos en SAFAR, no pagos externos."
        ),
        "budget.plan": "El presupuesto del viaje es {currency} {budget}.",
        "recommend.empty": (
            "Todavía no hay un lote de recomendaciones para este viaje. Abre el Motor de "
            "Experiencia de Grupo y elige Todos Ganan, Tu Turno o Sorpréndenos."
        ),
        "recommend.batch": "El último lote «{mode}» sugiere: {listing}.",
        "recommend.rec": "{name} (puntuación {score}, ajuste mínimo del miembro {fit})",
        "recommend.none_stored": "El último lote no tiene recomendaciones guardadas.",
        "recommend.limit": (
            "Las puntuaciones son resultados del modelo según los datos del viaje; revisa "
            "las explicaciones antes de aprobar."
        ),
        "recommend.proposals": (
            "Son propuestas, no cambios confirmados. El grupo decide antes de que cambie "
            "el plan."
        ),
        "vote.none": "No hay propuestas abiertas esperando una decisión.",
        "vote.open": (
            "Hay {count} propuesta(s) abierta(s): {titles}. El motor recomienda; el grupo "
            "decide."
        ),
        "members.names": "{count} miembro(s) activo(s): {names}.",
        "members.limit": (
            "Los presupuestos y preferencias privadas no se muestran a propósito."
        ),
        "privacy.answer": (
            "Los viajes y los recuerdos son privados por defecto. Compartir la ubicación "
            "es opcional y por tiempo limitado. Puedes retirar el consentimiento, "
            "exportar tus datos o eliminar tu cuenta desde Ajustes. Los encuentros entre "
            "viajeros requieren aceptación mutua, y la verificación de identidad no "
            "garantiza seguridad."
        ),
        "place.summary": (
            "{name}: estimación del catálogo {currency} {price} por persona, unos "
            "{minutes} minutos, esfuerzo {effort} de 5."
        ),
        "place.hours_recorded": (
            "Horario registrado: {hours}. Son datos del catálogo, no una fuente en vivo."
        ),
        "place.hours_missing": (
            "No hay horario registrado, así que no puedo confirmarlo."
        ),
        "place.stepfree": "El catálogo registra acceso sin escalones.",
        "place.access_unknown": (
            "La accesibilidad en silla de ruedas es desconocida; no la voy a suponer."
        ),
        "place.access_barriers": (
            "El catálogo registra barreras de accesibilidad para esta actividad."
        ),
        "place.reports_signal": (
            "Última señal de viajeros: {category}, {source}, frescura {freshness}."
        ),
        "place.reports_none": (
            "No hay informes recientes de viajeros sobre este lugar."
        ),
        "place.limit_availability": (
            "No hay API de disponibilidad, entradas o colas en vivo configurada."
        ),
        "place.limit_catalog": (
            "Los precios y horarios provienen del catálogo y pueden estar desactualizados."
        ),
        "clarify.ask": (
            "¿A qué día o actividad te refieres? Pregunto en vez de adivinar porque el "
            "itinerario puede cambiar durante el viaje."
        ),
        "language.note_mixed": (
            "Tu mensaje mezclaba {mixed} con {language}. Respondí en el idioma del que "
            "estoy más seguro; vuelve a preguntar en el idioma que prefieras."
        ),
        "language.note_unsupported": (
            "Detecté {script}, en el que aún no puedo responder. Las respuestas están "
            "disponibles en inglés, español, francés, alemán, portugués, italiano, hindi "
            "y japonés, así que esta respuesta está en {language}."
        ),
        "language.note_unknown": (
            "No pude identificar el idioma con seguridad, así que respondí en {language}. "
            "Puedes elegir un idioma explícitamente."
        ),
        "language.limit": (
            "Esta respuesta es una plantilla generada localmente a partir de los registros "
            "de SAFAR, no una traducción humana ni de un modelo."
        ),
        "action.itinerary": "Abrir itinerario",
        "action.engine": "Abrir el Motor de Grupo",
        "action.expenses": "Abrir gastos",
        "action.members": "Abrir miembros",
        "action.voting": "Abrir votación",
        "action.privacy": "Abrir ajustes de privacidad",
        "action.rescue": "Abrir Trip Rescue",
        "action.evidence": "Abrir el Pasaporte de Evidencia",
        "action.overview": "Abrir resumen del viaje",
        "action.review": "Revisar recomendaciones",
        "action.open_trip": "Abrir un viaje",
        "limit.no_llm": "No hay un LLM externo ni una API de viajes en vivo configurada.",
        "limit.trip_data": "Esta respuesta usa solo los registros del viaje en SAFAR.",
        "role.owner": "propietario",
        "role.admin": "administrador",
        "role.member": "miembro",
        "role.guest": "invitado",
    },
    "fr": {
        "general.capabilities": (
            "Je peux répondre à partir de l'itinéraire confirmé, des dépenses, des "
            "membres, des propositions ouvertes et des lots de recommandations de ce "
            "voyage, ou chercher une activité du catalogue par son nom. Aucun modèle d'IA "
            "externe n'est configuré, donc je n'affirme que ce que SAFAR a enregistré."
        ),
        "general.no_trip": (
            "Choisissez un espace de voyage et interrogez son itinéraire, son budget, ses "
            "membres, ses propositions ouvertes ou ses recommandations. Je n'affirme que "
            "ce que SAFAR a enregistré."
        ),
        "general.unknown": (
            "Je n'ai pas trouvé cela dans les données de ce voyage. Je peux aider avec "
            "l'itinéraire, le budget, les membres, les propositions ouvertes, les "
            "recommandations, les activités du catalogue et la météo lorsqu'un "
            "fournisseur est configuré."
        ),
        "overview.heading": "Voici ce que SAFAR a enregistré pour {name}.",
        "overview.facts": (
            "Destination {destination}. Dates du {start} au {end}, {nights} nuits. "
            "Groupe de {group_size}. Devise {currency}."
        ),
        "overview.itinerary": (
            "{confirmed} élément(s) confirmé(s) sur {days} jour(s) ; {protected} marqués "
            "comme temps protégé."
        ),
        "overview.budget": (
            "Budget du voyage {currency} {budget}. Dépenses suivies {currency} {spent}."
        ),
        "overview.no_budget": (
            "Aucun budget de voyage n'est défini, donc je ne vais pas l'estimer."
        ),
        "overview.limit": (
            "Les dates, budgets et coûts sont des données du voyage, pas des prix en direct."
        ),
        "weather.unavailable": (
            "Aucun fournisseur météo n'est configuré, je ne peux donc pas donner de "
            "prévisions. Je ne vais pas les inventer. Si la météo change, ouvrez Trip "
            "Rescue : il peut proposer des solutions en intérieur que le groupe approuve."
        ),
        "weather.forecast": (
            "Prévisions pour {place} par {provider} : {summary}. Ce sont des prévisions, "
            "pas des observations."
        ),
        "weather.day": (
            "{date} : {label}, {min_temp}–{max_temp} °C, risque de pluie {rain} %."
        ),
        "weather.limit": (
            "Open-Meteo prévoit la météo à partir de coordonnées arrondies. Cela peut se "
            "tromper et ne garantit pas la sécurité."
        ),
        "weather.no_location": (
            "Ce voyage n'a pas de coordonnées de destination, je ne peux donc pas demander "
            "de prévisions."
        ),
        "itinerary.empty": (
            "Aucun élément confirmé dans l'itinéraire pour l'instant. Ajoutez une activité "
            "ou lancez le Moteur d'Expérience de Groupe et laissez le groupe approuver une "
            "suggestion."
        ),
        "itinerary.plan": "Le {day}, le programme confirmé est : {listing}.",
        "itinerary.item": "{time} {title}",
        "itinerary.item_cost": "{time} {title} (~{currency} {cost})",
        "itinerary.limit": (
            "Ce sont des entrées confirmées du programme. Les durées de trajet sont des "
            "estimations, pas le trafic en direct."
        ),
        "itinerary.next_day": (
            "Le prochain jour avec des éléments confirmés est le {day}."
        ),
        "budget.total": (
            "Les dépenses de groupe suivies s'élèvent à {currency} {total}."
        ),
        "budget.mine_ahead": (
            "Votre position nette est {net} : le groupe vous doit votre part pour le moment."
        ),
        "budget.mine_behind": (
            "Votre position nette est {net} : vous devez votre part au groupe pour le moment."
        ),
        "budget.settlement": (
            "Prochain règlement suggéré : {from_name} paie {to_name} {currency} {amount}."
        ),
        "budget.track_only": (
            "SAFAR suit et calcule seulement ; il ne transfère pas d'argent."
        ),
        "budget.limit": (
            "Les soldes reflètent les dépenses saisies dans SAFAR, pas des paiements "
            "externes."
        ),
        "budget.plan": "Le budget du voyage est de {currency} {budget}.",
        "recommend.empty": (
            "Je n'ai pas encore de lot de recommandations pour ce voyage. Ouvrez le Moteur "
            "d'Expérience de Groupe et choisissez Tout le Monde Gagne, À Votre Tour ou "
            "Surprenez-nous."
        ),
        "recommend.batch": "Le dernier lot « {mode} » suggère : {listing}.",
        "recommend.rec": "{name} (score {score}, adéquation minimale membre {fit})",
        "recommend.none_stored": (
            "Le dernier lot ne contient aucune recommandation enregistrée."
        ),
        "recommend.limit": (
            "Les scores sont des résultats de modèle basés sur les données du voyage ; "
            "lisez les explications avant d'approuver."
        ),
        "recommend.proposals": (
            "Ce sont des propositions, pas des changements confirmés. Le groupe décide "
            "avant que le programme change."
        ),
        "vote.none": "Aucune proposition ouverte n'attend de décision.",
        "vote.open": (
            "{count} proposition(s) ouverte(s) : {titles}. Le moteur recommande ; le "
            "groupe décide."
        ),
        "members.names": "{count} membre(s) actif(s) : {names}.",
        "members.limit": (
            "Les budgets et préférences privés ne sont volontairement pas affichés."
        ),
        "privacy.answer": (
            "Les voyages et les souvenirs sont privés par défaut. Le partage de position "
            "est facultatif et limité dans le temps. Vous pouvez retirer votre "
            "consentement, exporter vos données ou supprimer votre compte depuis les "
            "Réglages. Les rencontres entre voyageurs exigent une acceptation mutuelle, et "
            "la vérification d'identité ne garantit pas la sécurité."
        ),
        "place.summary": (
            "{name} — estimation catalogue {currency} {price} par personne, environ "
            "{minutes} minutes, effort {effort} sur 5."
        ),
        "place.hours_recorded": (
            "Horaires enregistrés : {hours}. Ce sont des données de catalogue, pas un flux "
            "en direct."
        ),
        "place.hours_missing": (
            "Les horaires ne sont pas enregistrés, je ne peux donc pas les confirmer."
        ),
        "place.stepfree": "L'accès sans marche est enregistré dans le catalogue.",
        "place.access_unknown": (
            "L'accessibilité en fauteuil roulant est inconnue ; je ne vais pas la supposer."
        ),
        "place.access_barriers": (
            "Le catalogue signale des obstacles d'accessibilité pour cette activité."
        ),
        "place.reports_signal": (
            "Dernier signal des voyageurs : {category} — {source}, fraîcheur {freshness}."
        ),
        "place.reports_none": (
            "Aucun signalement récent de voyageurs pour ce lieu."
        ),
        "place.limit_availability": (
            "Aucune API de disponibilité, de billets ou de file d'attente en direct n'est "
            "configurée."
        ),
        "place.limit_catalog": (
            "Les prix et horaires viennent du catalogue et peuvent être obsolètes."
        ),
        "clarify.ask": (
            "De quel jour ou de quelle activité parlez-vous ? Je demande plutôt que de "
            "deviner car l'itinéraire peut changer pendant le voyage."
        ),
        "language.note_mixed": (
            "Votre message mélangeait {mixed} et {language}. J'ai répondu dans la langue "
            "où je suis le plus sûr ; reposez la question dans celle que vous préférez."
        ),
        "language.note_unsupported": (
            "J'ai détecté {script}, dans lequel je ne peux pas encore répondre. Les "
            "réponses sont disponibles en anglais, espagnol, français, allemand, "
            "portugais, italien, hindi et japonais, donc cette réponse est en {language}."
        ),
        "language.note_unknown": (
            "Je n'ai pas pu identifier la langue avec certitude, j'ai donc répondu en "
            "{language}. Vous pouvez choisir une langue explicitement."
        ),
        "language.limit": (
            "Cette réponse est un modèle généré localement à partir des données de SAFAR, "
            "pas une traduction humaine ou de modèle."
        ),
        "action.itinerary": "Ouvrir l'itinéraire",
        "action.engine": "Ouvrir le Moteur de Groupe",
        "action.expenses": "Ouvrir les dépenses",
        "action.members": "Ouvrir les membres",
        "action.voting": "Ouvrir le vote",
        "action.privacy": "Ouvrir les réglages de confidentialité",
        "action.rescue": "Ouvrir Trip Rescue",
        "action.evidence": "Ouvrir le Passeport de Preuves",
        "action.overview": "Ouvrir l'aperçu du voyage",
        "action.review": "Examiner les recommandations",
        "action.open_trip": "Ouvrir un voyage",
        "limit.no_llm": (
            "Aucun LLM externe ni API de voyage en direct n'est configuré."
        ),
        "limit.trip_data": (
            "Cette réponse utilise uniquement les données du voyage dans SAFAR."
        ),
        "role.owner": "propriétaire",
        "role.admin": "administrateur",
        "role.member": "membre",
        "role.guest": "invité",
    },
    "de": {
        "general.capabilities": (
            "Ich kann aus dem bestätigten Reiseplan, den Ausgaben, den Mitgliedern, den "
            "offenen Vorschlägen und den Empfehlungsstapeln dieser Reise antworten oder "
            "eine Katalogaktivität nach Namen suchen. Es ist kein externes KI-Modell "
            "konfiguriert, daher sage ich nur, was SAFAR tatsächlich gespeichert hat."
        ),
        "general.no_trip": (
            "Wähle einen Reisebereich und frage nach Reiseplan, Budget, Mitgliedern, "
            "offenen Vorschlägen oder Empfehlungen. Ich sage nur, was SAFAR gespeichert hat."
        ),
        "general.unknown": (
            "Das habe ich in den Daten dieser Reise nicht gefunden. Ich kann bei Reiseplan, "
            "Budget, Mitgliedern, offenen Vorschlägen, Empfehlungen, Katalogaktivitäten "
            "und – wenn ein Anbieter konfiguriert ist – beim Wetter helfen."
        ),
        "overview.heading": "Das hat SAFAR für {name} gespeichert.",
        "overview.facts": (
            "Ziel {destination}. Daten {start} bis {end}, {nights} Nächte. Gruppe mit "
            "{group_size} Personen. Währung {currency}."
        ),
        "overview.itinerary": (
            "{confirmed} bestätigte Einträge an {days} Tag(en); {protected} als geschützte "
            "Zeit markiert."
        ),
        "overview.budget": (
            "Reisebudget {currency} {budget}. Erfasste Ausgaben {currency} {spent}."
        ),
        "overview.no_budget": (
            "Es ist kein Reisebudget festgelegt, daher schätze ich keines."
        ),
        "overview.limit": (
            "Daten, Budgets und Kosten sind Reisedaten, keine Live-Preise."
        ),
        "weather.unavailable": (
            "Es ist kein Wetteranbieter konfiguriert, daher kann ich keine Vorhersage "
            "geben. Ich erfinde keine. Wenn sich das Wetter ändert, öffne Trip Rescue – es "
            "kann Alternativen für drinnen vorschlagen, die die Gruppe bestätigt."
        ),
        "weather.forecast": (
            "Vorhersage für {place} von {provider}: {summary}. Das ist eine Vorhersage, "
            "keine Beobachtung."
        ),
        "weather.day": (
            "{date}: {label}, {min_temp}–{max_temp} °C, Regenwahrscheinlichkeit {rain} %."
        ),
        "weather.limit": (
            "Open-Meteo sagt das Wetter aus gerundeten Koordinaten voraus. Es kann falsch "
            "sein und ist keine Sicherheitsgarantie."
        ),
        "weather.no_location": (
            "Diese Reise hat keine Zielkoordinaten, daher kann ich keine Vorhersage "
            "abrufen."
        ),
        "itinerary.empty": (
            "Es gibt noch keine bestätigten Reiseplaneinträge. Füge eine Aktivität hinzu "
            "oder starte die Gruppen-Engine und lass die Gruppe einen Vorschlag bestätigen."
        ),
        "itinerary.plan": "Am {day} ist der bestätigte Plan: {listing}.",
        "itinerary.item": "{time} {title}",
        "itinerary.item_cost": "{time} {title} (~{currency} {cost})",
        "itinerary.limit": (
            "Das sind bestätigte Planeinträge. Fahrzeiten sind Schätzungen, kein "
            "Live-Verkehr."
        ),
        "itinerary.next_day": "Der nächste Tag mit bestätigten Einträgen ist der {day}.",
        "budget.total": "Erfasste Gruppenausgaben: {currency} {total}.",
        "budget.mine_ahead": (
            "Deine Nettoposition ist {net} – die Gruppe schuldet dir derzeit deinen Anteil."
        ),
        "budget.mine_behind": (
            "Deine Nettoposition ist {net} – du schuldest der Gruppe derzeit deinen Anteil."
        ),
        "budget.settlement": (
            "Nächste vorgeschlagene Abrechnung: {from_name} zahlt {to_name} {currency} "
            "{amount}."
        ),
        "budget.track_only": (
            "SAFAR erfasst und rechnet nur; es bewegt kein Geld."
        ),
        "budget.limit": (
            "Salden spiegeln in SAFAR erfasste Ausgaben wider, nicht externe Zahlungen."
        ),
        "budget.plan": "Das Reisebudget beträgt {currency} {budget}.",
        "recommend.empty": (
            "Für diese Reise gibt es noch keinen Empfehlungsstapel. Öffne die "
            "Gruppen-Engine und wähle Alle Gewinnen, Du Bist Dran oder Überrasch Uns."
        ),
        "recommend.batch": "Der letzte Stapel „{mode}“ schlägt vor: {listing}.",
        "recommend.rec": "{name} (Wert {score}, minimale Mitgliedspassung {fit})",
        "recommend.none_stored": (
            "Der letzte Stapel enthält keine gespeicherten Empfehlungen."
        ),
        "recommend.limit": (
            "Werte sind Modellergebnisse auf Basis der Reisedaten; lies die Erklärungen "
            "vor der Zustimmung."
        ),
        "recommend.proposals": (
            "Das sind Vorschläge, keine bestätigten Änderungen. Die Gruppe entscheidet, "
            "bevor sich der Plan ändert."
        ),
        "vote.none": "Es warten keine offenen Vorschläge auf eine Entscheidung.",
        "vote.open": (
            "{count} offene(r) Vorschlag/Vorschläge: {titles}. Die Engine empfiehlt; die "
            "Gruppe entscheidet."
        ),
        "members.names": "{count} aktive(s) Mitglied(er): {names}.",
        "members.limit": (
            "Private Budgets und Vorlieben werden bewusst nicht angezeigt."
        ),
        "privacy.answer": (
            "Reisen und Erinnerungen sind standardmäßig privat. Standortfreigabe ist "
            "optional und zeitlich begrenzt. Du kannst deine Einwilligung widerrufen, "
            "deine Daten exportieren oder dein Konto in den Einstellungen löschen. "
            "Treffen zwischen Reisenden erfordern gegenseitige Zustimmung, und "
            "Identitätsprüfungen garantieren keine Sicherheit."
        ),
        "place.summary": (
            "{name} – Katalogschätzung {currency} {price} pro Person, etwa {minutes} "
            "Minuten, Anstrengung {effort} von 5."
        ),
        "place.hours_recorded": (
            "Erfasste Öffnungszeiten: {hours}. Das sind Katalogdaten, kein Live-Feed."
        ),
        "place.hours_missing": (
            "Öffnungszeiten sind nicht erfasst, daher kann ich sie nicht bestätigen."
        ),
        "place.stepfree": "Stufenloser Zugang ist im Katalog erfasst.",
        "place.access_unknown": (
            "Rollstuhlgerechtigkeit ist unbekannt; ich nehme sie nicht an."
        ),
        "place.access_barriers": (
            "Der Katalog erfasst Barrierefreiheitshindernisse für diese Aktivität."
        ),
        "place.reports_signal": (
            "Letztes Reisendensignal: {category} – {source}, Aktualität {freshness}."
        ),
        "place.reports_none": (
            "Es gibt keine aktuellen Reisendenberichte zu diesem Ort."
        ),
        "place.limit_availability": (
            "Es ist keine Live-API für Verfügbarkeit, Tickets oder Warteschlangen "
            "konfiguriert."
        ),
        "place.limit_catalog": (
            "Preise und Zeiten stammen aus dem Katalogeintrag und können veraltet sein."
        ),
        "clarify.ask": (
            "Welchen Tag oder welche Aktivität meinst du? Ich frage, statt zu raten, weil "
            "sich der Reiseplan während der Reise ändern kann."
        ),
        "language.note_mixed": (
            "Deine Nachricht mischte {mixed} und {language}. Ich habe in der Sprache "
            "geantwortet, bei der ich am sichersten bin; frage gern in beiden erneut."
        ),
        "language.note_unsupported": (
            "Ich habe {script} erkannt, kann darin aber noch nicht antworten. Antworten "
            "gibt es auf Englisch, Spanisch, Französisch, Deutsch, Portugiesisch, "
            "Italienisch, Hindi und Japanisch, daher ist diese Antwort auf {language}."
        ),
        "language.note_unknown": (
            "Ich konnte die Sprache nicht sicher erkennen, daher habe ich auf {language} "
            "geantwortet. Du kannst eine Sprache ausdrücklich wählen."
        ),
        "language.limit": (
            "Diese Antwort ist eine lokal aus SAFAR-Daten erzeugte Vorlage, keine "
            "menschliche oder Modellübersetzung."
        ),
        "action.itinerary": "Reiseplan öffnen",
        "action.engine": "Gruppen-Engine öffnen",
        "action.expenses": "Ausgaben öffnen",
        "action.members": "Mitglieder öffnen",
        "action.voting": "Abstimmung öffnen",
        "action.privacy": "Datenschutzeinstellungen öffnen",
        "action.rescue": "Trip Rescue öffnen",
        "action.evidence": "Entscheidungs-Pass öffnen",
        "action.overview": "Reiseübersicht öffnen",
        "action.review": "Empfehlungen prüfen",
        "action.open_trip": "Eine Reise öffnen",
        "limit.no_llm": (
            "Es ist kein externes LLM und keine Live-Reise-API konfiguriert."
        ),
        "limit.trip_data": (
            "Diese Antwort nutzt nur die Reisedaten in SAFAR."
        ),
        "role.owner": "Eigentümer",
        "role.admin": "Administrator",
        "role.member": "Mitglied",
        "role.guest": "Gast",
    },
    "pt": {
        "general.capabilities": (
            "Posso responder com o itinerário confirmado, as despesas, os membros, as "
            "propostas abertas e os lotes de recomendações desta viagem, ou procurar uma "
            "atividade do catálogo pelo nome. Não há um modelo de IA externo configurado, "
            "por isso só digo o que a SAFAR tem registado."
        ),
        "general.no_trip": (
            "Escolhe um espaço de viagem e pergunta pelo itinerário, orçamento, membros, "
            "propostas abertas ou recomendações. Só digo o que a SAFAR registou."
        ),
        "general.unknown": (
            "Não encontrei isso nos registos desta viagem. Posso ajudar com o itinerário, "
            "o orçamento, os membros, as propostas abertas, as recomendações, as "
            "atividades do catálogo e o tempo quando há um fornecedor configurado."
        ),
        "overview.heading": "Isto é o que a SAFAR registou para {name}.",
        "overview.facts": (
            "Destino {destination}. Datas de {start} a {end}, {nights} noites. Grupo de "
            "{group_size}. Moeda {currency}."
        ),
        "overview.itinerary": (
            "{confirmed} item(ns) confirmado(s) em {days} dia(s); {protected} marcados "
            "como tempo protegido."
        ),
        "overview.budget": (
            "Orçamento da viagem {currency} {budget}. Despesa registada {currency} {spent}."
        ),
        "overview.no_budget": (
            "Não há orçamento de viagem definido, por isso não vou estimá-lo."
        ),
        "overview.limit": (
            "Datas, orçamentos e custos são registos da viagem, não preços ao vivo."
        ),
        "weather.unavailable": (
            "Não tenho um fornecedor de meteorologia configurado, por isso não posso dar a "
            "previsão. Não a vou inventar. Se o tempo mudar, abre o Trip Rescue e ele pode "
            "propor alternativas em interior para o grupo aprovar."
        ),
        "weather.forecast": (
            "Previsão para {place} de {provider}: {summary}. É uma previsão, não uma "
            "observação."
        ),
        "weather.day": (
            "{date}: {label}, {min_temp}–{max_temp} °C, probabilidade de chuva {rain}%."
        ),
        "weather.limit": (
            "A Open-Meteo prevê o tempo a partir de coordenadas arredondadas. Pode errar e "
            "não é uma garantia de segurança."
        ),
        "weather.no_location": (
            "Esta viagem não tem coordenadas de destino, por isso não posso pedir previsão."
        ),
        "itinerary.empty": (
            "Ainda não há itens confirmados no itinerário. Adiciona uma atividade ou corre "
            "o Motor de Experiência de Grupo e deixa o grupo aprovar uma sugestão."
        ),
        "itinerary.plan": "A {day} o plano confirmado é: {listing}.",
        "itinerary.item": "{time} {title}",
        "itinerary.item_cost": "{time} {title} (~{currency} {cost})",
        "itinerary.limit": (
            "São entradas confirmadas do plano. As durações de deslocação são estimativas, "
            "não trânsito ao vivo."
        ),
        "itinerary.next_day": "O próximo dia com itens confirmados é {day}.",
        "budget.total": "A despesa de grupo registada é {currency} {total}.",
        "budget.mine_ahead": (
            "A tua posição líquida é {net} — o grupo deve-te a tua parte por agora."
        ),
        "budget.mine_behind": (
            "A tua posição líquida é {net} — deves a tua parte ao grupo por agora."
        ),
        "budget.settlement": (
            "Próxima liquidação sugerida: {from_name} paga a {to_name} {currency} {amount}."
        ),
        "budget.track_only": "A SAFAR apenas registra e calcula; não move dinheiro.",
        "budget.limit": (
            "Os saldos refletem despesas introduzidas na SAFAR, não pagamentos externos."
        ),
        "budget.plan": "O orçamento da viagem é {currency} {budget}.",
        "recommend.empty": (
            "Ainda não há um lote de recomendações para esta viagem. Abre o Motor de "
            "Experiência de Grupo e escolhe Todos Ganham, A Tua Vez ou Surpreende-nos."
        ),
        "recommend.batch": "O último lote «{mode}» sugere: {listing}.",
        "recommend.rec": "{name} (pontuação {score}, ajuste mínimo do membro {fit})",
        "recommend.none_stored": "O último lote não tem recomendações guardadas.",
        "recommend.limit": (
            "As pontuações são resultados do modelo com base nos dados da viagem; revê as "
            "explicações antes de aprovar."
        ),
        "recommend.proposals": (
            "São propostas, não alterações confirmadas. O grupo decide antes de o plano "
            "mudar."
        ),
        "vote.none": "Não há propostas abertas à espera de decisão.",
        "vote.open": (
            "{count} proposta(s) aberta(s): {titles}. O motor recomenda; o grupo decide."
        ),
        "members.names": "{count} membro(s) ativo(s): {names}.",
        "members.limit": (
            "Orçamentos e preferências privadas não são mostrados de propósito."
        ),
        "privacy.answer": (
            "As viagens e as memórias são privadas por defeito. Partilhar a localização é "
            "opcional e limitado no tempo. Podes retirar o consentimento, exportar os teus "
            "dados ou eliminar a conta nas Definições. Os encontros entre viajantes exigem "
            "aceitação mútua, e a verificação de identidade não garante segurança."
        ),
        "place.summary": (
            "{name} — estimativa do catálogo {currency} {price} por pessoa, cerca de "
            "{minutes} minutos, esforço {effort} de 5."
        ),
        "place.hours_recorded": (
            "Horário registado: {hours}. São dados do catálogo, não uma fonte ao vivo."
        ),
        "place.hours_missing": (
            "O horário não está registado, por isso não o posso confirmar."
        ),
        "place.stepfree": "O acesso sem degraus está registado no catálogo.",
        "place.access_unknown": (
            "A acessibilidade em cadeira de rodas é desconhecida; não vou assumi-la."
        ),
        "place.access_barriers": (
            "O catálogo regista barreiras de acessibilidade para esta atividade."
        ),
        "place.reports_signal": (
            "Último sinal de viajantes: {category} — {source}, atualidade {freshness}."
        ),
        "place.reports_none": (
            "Não há relatos recentes de viajantes sobre este lugar."
        ),
        "place.limit_availability": (
            "Não há API de disponibilidade, bilhetes ou filas ao vivo configurada."
        ),
        "place.limit_catalog": (
            "Preços e horários vêm do catálogo e podem estar desatualizados."
        ),
        "clarify.ask": (
            "A que dia ou atividade te referes? Pergunto em vez de adivinhar porque o "
            "itinerário pode mudar durante a viagem."
        ),
        "language.note_mixed": (
            "A tua mensagem misturava {mixed} com {language}. Respondi no idioma em que "
            "tenho mais confiança; pergunta de novo em qualquer um dos dois."
        ),
        "language.note_unsupported": (
            "Detetei {script}, no qual ainda não consigo responder. As respostas estão "
            "disponíveis em inglês, espanhol, francês, alemão, português, italiano, hindi "
            "e japonês, por isso esta resposta está em {language}."
        ),
        "language.note_unknown": (
            "Não consegui identificar o idioma com confiança, por isso respondi em "
            "{language}. Podes escolher um idioma explicitamente."
        ),
        "language.limit": (
            "Esta resposta é um modelo gerado localmente a partir dos registos da SAFAR, "
            "não uma tradução humana ou de modelo."
        ),
        "action.itinerary": "Abrir itinerário",
        "action.engine": "Abrir o Motor de Grupo",
        "action.expenses": "Abrir despesas",
        "action.members": "Abrir membros",
        "action.voting": "Abrir votação",
        "action.privacy": "Abrir definições de privacidade",
        "action.rescue": "Abrir Trip Rescue",
        "action.evidence": "Abrir o Passaporte de Evidência",
        "action.overview": "Abrir resumo da viagem",
        "action.review": "Rever recomendações",
        "action.open_trip": "Abrir uma viagem",
        "limit.no_llm": (
            "Não há um LLM externo nem uma API de viagens ao vivo configurada."
        ),
        "limit.trip_data": "Esta resposta usa apenas os registos da viagem na SAFAR.",
        "role.owner": "proprietário",
        "role.admin": "administrador",
        "role.member": "membro",
        "role.guest": "convidado",
    },
    "it": {
        "general.capabilities": (
            "Posso rispondere con l'itinerario confermato, le spese, i membri, le proposte "
            "aperte e i lotti di raccomandazioni di questo viaggio, oppure cercare "
            "un'attività del catalogo per nome. Non è configurato alcun modello di IA "
            "esterno, quindi dico solo ciò che SAFAR ha registrato."
        ),
        "general.no_trip": (
            "Scegli uno spazio viaggio e chiedi del suo itinerario, budget, membri, "
            "proposte aperte o raccomandazioni. Dico solo ciò che SAFAR ha registrato."
        ),
        "general.unknown": (
            "Non l'ho trovato nei dati di questo viaggio. Posso aiutare con itinerario, "
            "budget, membri, proposte aperte, raccomandazioni, attività del catalogo e "
            "meteo quando è configurato un fornitore."
        ),
        "overview.heading": "Ecco cosa ha registrato SAFAR per {name}.",
        "overview.facts": (
            "Destinazione {destination}. Date dal {start} al {end}, {nights} notti. "
            "Gruppo di {group_size}. Valuta {currency}."
        ),
        "overview.itinerary": (
            "{confirmed} elemento/i confermato/i in {days} giorno/i; {protected} segnati "
            "come tempo protetto."
        ),
        "overview.budget": (
            "Budget del viaggio {currency} {budget}. Spese registrate {currency} {spent}."
        ),
        "overview.no_budget": (
            "Nessun budget di viaggio è impostato, quindi non lo stimerò."
        ),
        "overview.limit": (
            "Date, budget e costi sono dati del viaggio, non prezzi in tempo reale."
        ),
        "weather.unavailable": (
            "Non ho un fornitore meteo configurato, quindi non posso darti le previsioni. "
            "Non le inventerò. Se il tempo cambia, apri Trip Rescue: può proporre "
            "alternative al coperto che il gruppo approva."
        ),
        "weather.forecast": (
            "Previsioni per {place} da {provider}: {summary}. Sono previsioni, non "
            "osservazioni."
        ),
        "weather.day": (
            "{date}: {label}, {min_temp}–{max_temp} °C, probabilità di pioggia {rain}%."
        ),
        "weather.limit": (
            "Open-Meteo prevede il tempo da coordinate arrotondate. Può sbagliare e non è "
            "una garanzia di sicurezza."
        ),
        "weather.no_location": (
            "Questo viaggio non ha coordinate della destinazione, quindi non posso "
            "richiedere previsioni."
        ),
        "itinerary.empty": (
            "Non ci sono ancora elementi confermati nell'itinerario. Aggiungi un'attività "
            "o avvia il Motore di Esperienza di Gruppo e lascia che il gruppo approvi un "
            "suggerimento."
        ),
        "itinerary.plan": "Il {day} il piano confermato è: {listing}.",
        "itinerary.item": "{time} {title}",
        "itinerary.item_cost": "{time} {title} (~{currency} {cost})",
        "itinerary.limit": (
            "Sono voci confermate del piano. Le durate di spostamento sono stime, non "
            "traffico in tempo reale."
        ),
        "itinerary.next_day": "Il prossimo giorno con elementi confermati è il {day}.",
        "budget.total": "La spesa di gruppo registrata è {currency} {total}.",
        "budget.mine_ahead": (
            "La tua posizione netta è {net}: per ora il gruppo ti deve la tua parte."
        ),
        "budget.mine_behind": (
            "La tua posizione netta è {net}: per ora devi la tua parte al gruppo."
        ),
        "budget.settlement": (
            "Prossimo saldo suggerito: {from_name} paga {to_name} {currency} {amount}."
        ),
        "budget.track_only": (
            "SAFAR registra e calcola soltanto; non sposta denaro."
        ),
        "budget.limit": (
            "I saldi riflettono le spese inserite in SAFAR, non pagamenti esterni."
        ),
        "budget.plan": "Il budget del viaggio è {currency} {budget}.",
        "recommend.empty": (
            "Non c'è ancora un lotto di raccomandazioni per questo viaggio. Apri il Motore "
            "di Esperienza di Gruppo e scegli Tutti Vincenti, Il Tuo Turno o Sorprendici."
        ),
        "recommend.batch": "L'ultimo lotto «{mode}» suggerisce: {listing}.",
        "recommend.rec": "{name} (punteggio {score}, adattamento minimo membro {fit})",
        "recommend.none_stored": (
            "L'ultimo lotto non ha raccomandazioni salvate."
        ),
        "recommend.limit": (
            "I punteggi sono risultati del modello basati sui dati del viaggio; leggi le "
            "spiegazioni prima di approvare."
        ),
        "recommend.proposals": (
            "Sono proposte, non modifiche confermate. Il gruppo decide prima che il piano "
            "cambi."
        ),
        "vote.none": "Non ci sono proposte aperte in attesa di una decisione.",
        "vote.open": (
            "{count} proposta/e aperta/e: {titles}. Il motore raccomanda; il gruppo "
            "decide."
        ),
        "members.names": "{count} membro/i attivo/i: {names}.",
        "members.limit": (
            "Budget e preferenze privati non vengono mostrati di proposito."
        ),
        "privacy.answer": (
            "I viaggi e i ricordi sono privati per impostazione predefinita. La "
            "condivisione della posizione è facoltativa e a tempo. Puoi revocare il "
            "consenso, esportare i tuoi dati o eliminare l'account dalle Impostazioni. Gli "
            "incontri tra viaggiatori richiedono accettazione reciproca e la verifica "
            "dell'identità non garantisce sicurezza."
        ),
        "place.summary": (
            "{name} — stima del catalogo {currency} {price} a persona, circa {minutes} "
            "minuti, impegno {effort} su 5."
        ),
        "place.hours_recorded": (
            "Orari registrati: {hours}. Sono dati del catalogo, non un feed in tempo reale."
        ),
        "place.hours_missing": (
            "Gli orari non sono registrati, quindi non posso confermarli."
        ),
        "place.stepfree": "L'accesso senza gradini è registrato nel catalogo.",
        "place.access_unknown": (
            "L'accessibilità in sedia a rotelle è sconosciuta; non la presumerò."
        ),
        "place.access_barriers": (
            "Il catalogo registra barriere di accessibilità per questa attività."
        ),
        "place.reports_signal": (
            "Ultimo segnale dei viaggiatori: {category} — {source}, freschezza "
            "{freshness}."
        ),
        "place.reports_none": (
            "Non ci sono segnalazioni recenti dei viaggiatori su questo luogo."
        ),
        "place.limit_availability": (
            "Nessuna API di disponibilità, biglietti o code in tempo reale è configurata."
        ),
        "place.limit_catalog": (
            "Prezzi e orari provengono dal catalogo e possono essere obsoleti."
        ),
        "clarify.ask": (
            "A quale giorno o attività ti riferisci? Chiedo invece di indovinare perché "
            "l'itinerario può cambiare durante il viaggio."
        ),
        "language.note_mixed": (
            "Il tuo messaggio mescolava {mixed} e {language}. Ho risposto nella lingua di "
            "cui sono più sicuro; chiedi di nuovo in quella che preferisci."
        ),
        "language.note_unsupported": (
            "Ho rilevato {script}, in cui non posso ancora rispondere. Le risposte sono "
            "disponibili in inglese, spagnolo, francese, tedesco, portoghese, italiano, "
            "hindi e giapponese, quindi questa risposta è in {language}."
        ),
        "language.note_unknown": (
            "Non ho identificato la lingua con sicurezza, quindi ho risposto in "
            "{language}. Puoi scegliere una lingua esplicitamente."
        ),
        "language.limit": (
            "Questa risposta è un modello generato localmente dai dati di SAFAR, non una "
            "traduzione umana o di un modello."
        ),
        "action.itinerary": "Apri itinerario",
        "action.engine": "Apri il Motore di Gruppo",
        "action.expenses": "Apri spese",
        "action.members": "Apri membri",
        "action.voting": "Apri votazione",
        "action.privacy": "Apri impostazioni privacy",
        "action.rescue": "Apri Trip Rescue",
        "action.evidence": "Apri il Passaporto delle Prove",
        "action.overview": "Apri panoramica del viaggio",
        "action.review": "Esamina le raccomandazioni",
        "action.open_trip": "Apri un viaggio",
        "limit.no_llm": (
            "Nessun LLM esterno e nessuna API di viaggio in tempo reale è configurata."
        ),
        "limit.trip_data": "Questa risposta usa solo i dati del viaggio in SAFAR.",
        "role.owner": "proprietario",
        "role.admin": "amministratore",
        "role.member": "membro",
        "role.guest": "ospite",
    },
    "hi": {
        "general.capabilities": (
            "मैं इस यात्रा के पुष्ट इतिनेरी, खर्च, सदस्यों, खुली प्रस्तावों और सिफ़ारिश "
            "बैच से जवाब दे सकता हूँ, या नाम से कैटलॉग गतिविधि खोज सकता हूँ। कोई बाहरी "
            "AI मॉडल कॉन्फ़िगर नहीं है, इसलिए मैं केवल वही बताता हूँ जो SAFAR में दर्ज है।"
        ),
        "general.no_trip": (
            "कोई यात्रा चुनें और उसके इतिनेरी, बजट, सदस्यों, खुली प्रस्तावों या "
            "सिफ़ारिशों के बारे में पूछें। मैं केवल वही बताता हूँ जो SAFAR में दर्ज है।"
        ),
        "general.unknown": (
            "मुझे यह इस यात्रा के रिकॉर्ड में नहीं मिला। मैं इतिनेरी, बजट, सदस्य, "
            "खुली प्रस्ताव, सिफ़ारिशें, कैटलॉग गतिविधियाँ और मौसम प्रदाता कॉन्फ़िगर होने पर "
            "मौसम में मदद कर सकता हूँ।"
        ),
        "overview.heading": "{name} के लिए SAFAR में यह दर्ज है।",
        "overview.facts": (
            "गंतव्य {destination}। तारीखें {start} से {end}, {nights} रातें। समूह "
            "{group_size} लोगों का। मुद्रा {currency}।"
        ),
        "overview.itinerary": (
            "{days} दिनों में {confirmed} पुष्ट इतिनेरी आइटम; {protected} संरक्षित समय "
            "के रूप में चिह्नित।"
        ),
        "overview.budget": (
            "यात्रा बजट {currency} {budget}। दर्ज खर्च {currency} {spent}।"
        ),
        "overview.no_budget": (
            "कोई यात्रा बजट तय नहीं है, इसलिए मैं इसका अनुमान नहीं लगाऊँगा।"
        ),
        "overview.limit": (
            "तारीखें, बजट और लागत यात्रा रिकॉर्ड हैं, लाइव कीमतें नहीं।"
        ),
        "weather.unavailable": (
            "मौसम प्रदाता कॉन्फ़िगर नहीं है, इसलिए मैं पूर्वानुमान नहीं दे सकता। मैं इसे "
            "बना कर नहीं बताऊँगा। मौसम बदले तो Trip Rescue खोलें—यह समूह की स्वीकृति के "
            "लिए इनडोर विकल्प प्रस्तावित कर सकता है।"
        ),
        "weather.forecast": (
            "{provider} से {place} का पूर्वानुमान: {summary}। यह पूर्वानुमान है, अवलोकन "
            "नहीं।"
        ),
        "weather.day": (
            "{date}: {label}, {min_temp}–{max_temp} °C, बारिश की संभावना {rain}%।"
        ),
        "weather.limit": (
            "Open-Meteo गोल किए गए निर्देशांक से मौसम का पूर्वानुमान लगाता है। यह गलत हो "
            "सकता है और सुरक्षा की गारंटी नहीं है।"
        ),
        "weather.no_location": (
            "इस यात्रा में गंतव्य के निर्देशांक नहीं हैं, इसलिए मैं पूर्वानुमान नहीं माँग "
            "सकता।"
        ),
        "itinerary.empty": (
            "अभी कोई पुष्ट इतिनेरी आइटम नहीं है। कोई गतिविधि जोड़ें, या Group Experience "
            "Engine चलाएँ और समूह से सुझाव स्वीकृत कराएँ।"
        ),
        "itinerary.plan": "{day} को पुष्ट योजना है: {listing}।",
        "itinerary.item": "{time} {title}",
        "itinerary.item_cost": "{time} {title} (~{currency} {cost})",
        "itinerary.limit": (
            "ये पुष्ट योजना प्रविष्टियाँ हैं। यात्रा समय अनुमान हैं, लाइव ट्रैफ़िक नहीं।"
        ),
        "itinerary.next_day": (
            "पुष्ट आइटम वाला अगला दिन {day} है।"
        ),
        "budget.total": "दर्ज समूह खर्च {currency} {total} है।",
        "budget.mine_ahead": (
            "आपकी शुद्ध स्थिति {net} है — अभी समूह आपको आपका हिस्सा देता है।"
        ),
        "budget.mine_behind": (
            "आपकी शुद्ध स्थिति {net} है — अभी आप समूह को अपना हिस्सा देते हैं।"
        ),
        "budget.settlement": (
            "अगला सुझाया निपटान: {from_name} {to_name} को {currency} {amount} दे।"
        ),
        "budget.track_only": "SAFAR केवल दर्ज और गणना करता है; पैसा नहीं भेजता।",
        "budget.limit": (
            "शेष राशि SAFAR में दर्ज खर्च दर्शाती है, बाहरी भुगतान नहीं।"
        ),
        "budget.plan": "यात्रा बजट {currency} {budget} है।",
        "recommend.empty": (
            "इस यात्रा के लिए अभी कोई सिफ़ारिश बैच नहीं है। Group Experience Engine "
            "खोलें और Everyone Wins, Your Turn या Surprise Us चुनें।"
        ),
        "recommend.batch": "नवीनतम {mode} बैच सुझाता है: {listing}।",
        "recommend.rec": "{name} (स्कोर {score}, न्यूनतम सदस्य फ़िट {fit})",
        "recommend.none_stored": "नवीनतम बैच में कोई संग्रहीत सिफ़ारिश नहीं है।",
        "recommend.limit": (
            "स्कोर उपलब्ध यात्रा डेटा पर आधारित मॉडल आउटपुट हैं; स्वीकृति से पहले "
            "व्याख्या पढ़ें।"
        ),
        "recommend.proposals": (
            "ये प्रस्ताव हैं, पुष्ट बदलाव नहीं। योजना बदलने से पहले समूह तय करता है।"
        ),
        "vote.none": "निर्णय की प्रतीक्षा में कोई खुला प्रस्ताव नहीं है।",
        "vote.open": (
            "{count} खुले प्रस्ताव: {titles}। इंजन सुझाता है; समूह तय करता है।"
        ),
        "members.names": "{count} सक्रिय सदस्य: {names}।",
        "members.limit": "निजी बजट और प्राथमिकताएँ जानबूझकर नहीं दिखाई जातीं।",
        "privacy.answer": (
            "यात्राएँ और यादें डिफ़ॉल्ट रूप से निजी हैं। स्थान साझा करना वैकल्पिक और "
            "समय-सीमित है। आप Settings से सहमति वापस ले सकते हैं, अपना डेटा निर्यात कर "
            "सकते हैं या खाता हटा सकते हैं। यात्री मुलाक़ातों के लिए आपसी स्वीकृति आवश्यक "
            "है, और पहचान जाँच सुरक्षा की गारंटी नहीं देती।"
        ),
        "place.summary": (
            "{name} — कैटलॉग अनुमान {currency} {price} प्रति व्यक्ति, लगभग {minutes} "
            "मिनट, कठिनाई 5 में से {effort}।"
        ),
        "place.hours_recorded": (
            "दर्ज खुलने का समय: {hours}। यह कैटलॉग डेटा है, लाइव फ़ीड नहीं।"
        ),
        "place.hours_missing": (
            "खुलने का समय दर्ज नहीं है, इसलिए मैं इसकी पुष्टि नहीं कर सकता।"
        ),
        "place.stepfree": "कैटलॉग में बिना सीढ़ी वाली पहुँच दर्ज है।",
        "place.access_unknown": (
            "व्हीलचेयर सुगम्यता अज्ञात है; मैं इसे मान नहीं लूँगा।"
        ),
        "place.access_barriers": (
            "कैटलॉग इस गतिविधि के लिए सुगम्यता बाधाएँ दर्ज करता है।"
        ),
        "place.reports_signal": (
            "नवीनतम यात्री संकेत: {category} — {source}, ताज़गी {freshness}।"
        ),
        "place.reports_none": (
            "इस स्थान के लिए कोई हालिया यात्री रिपोर्ट नहीं है।"
        ),
        "place.limit_availability": (
            "कोई लाइव उपलब्धता, टिकट या कतार API कॉन्फ़िगर नहीं है।"
        ),
        "place.limit_catalog": (
            "कीमतें और समय कैटलॉग रिकॉर्ड से हैं और पुराने हो सकते हैं।"
        ),
        "clarify.ask": (
            "आप किस दिन या गतिविधि की बात कर रहे हैं? मैं अनुमान लगाने के बजाय पूछता "
            "हूँ क्योंकि यात्रा के दौरान इतिनेरी बदल सकता है।"
        ),
        "language.note_mixed": (
            "आपके संदेश में {mixed} और {language} मिश्रित थे। मैंने उस भाषा में जवाब दिया "
            "जिसमें मुझे सबसे अधिक भरोसा है; किसी भी भाषा में फिर पूछें।"
        ),
        "language.note_unsupported": (
            "मैंने {script} पहचानी, जिसमें मैं अभी जवाब नहीं दे सकता। जवाब अंग्रेज़ी, "
            "स्पेनिश, फ़्रेंच, जर्मन, पुर्तगाली, इतालवी, हिंदी और जापानी में उपलब्ध हैं, "
            "इसलिए यह उत्तर {language} में है।"
        ),
        "language.note_unknown": (
            "मैं भाषा निश्चित रूप से नहीं पहचान सका, इसलिए मैंने {language} में जवाब "
            "दिया। आप भाषा स्पष्ट रूप से चुन सकते हैं।"
        ),
        "language.limit": (
            "यह SAFAR रिकॉर्ड से स्थानीय रूप से बनाया गया टेम्पलेट उत्तर है, मानव या "
            "मॉडल अनुवाद नहीं।"
        ),
        "action.itinerary": "इतिनेरी खोलें",
        "action.engine": "Group Engine खोलें",
        "action.expenses": "खर्च खोलें",
        "action.members": "सदस्य खोलें",
        "action.voting": "मतदान खोलें",
        "action.privacy": "गोपनीयता सेटिंग्स खोलें",
        "action.rescue": "Trip Rescue खोलें",
        "action.evidence": "निर्णय प्रमाण पासपोर्ट खोलें",
        "action.overview": "यात्रा अवलोकन खोलें",
        "action.review": "सिफ़ारिशें देखें",
        "action.open_trip": "यात्रा खोलें",
        "limit.no_llm": "कोई बाहरी LLM या लाइव यात्रा API कॉन्फ़िगर नहीं है।",
        "limit.trip_data": "यह उत्तर केवल SAFAR यात्रा रिकॉर्ड का उपयोग करता है।",
        "role.owner": "मालिक",
        "role.admin": "व्यवस्थापक",
        "role.member": "सदस्य",
        "role.guest": "अतिथि",
    },
    "ja": {
        "general.capabilities": (
            "この旅行の確定済み旅程、費用、メンバー、未決の提案、推薦バッチから回答でき、"
            "カタログのアクティビティを名前で検索できます。外部AIモデルは設定されていない"
            "ため、SAFARに記録されていることだけを伝えます。"
        ),
        "general.no_trip": (
            "旅行を選び、旅程・予算・メンバー・未決の提案・推薦について質問してください。"
            "SAFARに記録されていることだけを伝えます。"
        ),
        "general.unknown": (
            "この旅行の記録には見つかりませんでした。旅程、予算、メンバー、未決の提案、"
            "推薦、カタログのアクティビティ、天気プロバイダーが設定されていれば天気について"
            "お手伝いできます。"
        ),
        "overview.heading": "{name} についてSAFARに記録されている内容です。",
        "overview.facts": (
            "目的地 {destination}。日程 {start} から {end}、{nights} 泊。グループ "
            "{group_size} 人。通貨 {currency}。"
        ),
        "overview.itinerary": (
            "{days} 日間に確定済み旅程 {confirmed} 件、うち {protected} 件が保護時間です。"
        ),
        "overview.budget": (
            "旅行予算 {currency} {budget}。記録済み支出 {currency} {spent}。"
        ),
        "overview.no_budget": "旅行予算が設定されていないため、推測はしません。",
        "overview.limit": "日程・予算・費用は旅行の記録であり、最新の価格ではありません。",
        "weather.unavailable": (
            "天気プロバイダーが設定されていないため、予報はお伝えできません。推測は"
            "しません。天候が変わったら Trip Rescue を開いてください。グループの承認を"
            "得て屋内の代替案を提案できます。"
        ),
        "weather.forecast": (
            "{provider} による {place} の予報: {summary}。これは予測であり観測では"
            "ありません。"
        ),
        "weather.day": (
            "{date}: {label}、{min_temp}〜{max_temp} °C、降水確率 {rain}%。"
        ),
        "weather.limit": (
            "Open-Meteo は丸めた座標から天気を予測します。外れることがあり、安全を保証"
            "するものではありません。"
        ),
        "weather.no_location": (
            "この旅行には目的地の座標がないため、予報を取得できません。"
        ),
        "itinerary.empty": (
            "確定済みの旅程はまだありません。アクティビティを追加するか、Group Experience "
            "Engine を実行してグループに提案を承認してもらってください。"
        ),
        "itinerary.plan": "{day} の確定プランは次のとおりです: {listing}。",
        "itinerary.item": "{time} {title}",
        "itinerary.item_cost": "{time} {title}（約 {currency} {cost}）",
        "itinerary.limit": (
            "これは確定済みのプランです。移動時間は推定であり、リアルタイムの交通情報"
            "ではありません。"
        ),
        "itinerary.next_day": "確定済み項目がある次の日は {day} です。",
        "budget.total": "記録済みのグループ支出は {currency} {total} です。",
        "budget.mine_ahead": (
            "あなたの純額は {net} です。現在はグループがあなたの分を負担しています。"
        ),
        "budget.mine_behind": (
            "あなたの純額は {net} です。現在はあなたがグループに自分の分を負担しています。"
        ),
        "budget.settlement": (
            "次回の精算案: {from_name} が {to_name} に {currency} {amount} 支払います。"
        ),
        "budget.track_only": "SAFAR は記録と計算のみを行い、送金はしません。",
        "budget.limit": (
            "残高は SAFAR に入力された支出を反映しており、外部の支払いではありません。"
        ),
        "budget.plan": "旅行予算は {currency} {budget} です。",
        "recommend.empty": (
            "この旅行の推薦バッチはまだありません。Group Experience Engine を開き、"
            "Everyone Wins、Your Turn、Surprise Us のいずれかを選んでください。"
        ),
        "recommend.batch": "最新の「{mode}」バッチの提案: {listing}。",
        "recommend.rec": "{name}（スコア {score}、メンバー最小適合 {fit}）",
        "recommend.none_stored": "最新バッチに保存された推薦はありません。",
        "recommend.limit": (
            "スコアは利用可能な旅行データに基づくモデル出力です。承認前に説明を確認"
            "してください。"
        ),
        "recommend.proposals": (
            "これは提案であり、確定した変更ではありません。プランが変わる前にグループが"
            "決定します。"
        ),
        "vote.none": "決定待ちの未決提案はありません。",
        "vote.open": (
            "未決の提案が {count} 件あります: {titles}。エンジンは推薦し、グループが"
            "決定します。"
        ),
        "members.names": "アクティブなメンバー {count} 人: {names}。",
        "members.limit": "個人の予算と好みは意図的に表示していません。",
        "privacy.answer": (
            "旅行とメモリーは既定で非公開です。位置情報の共有は任意で時間制限があり"
            "ます。設定から同意を撤回し、データを書き出し、アカウントを削除できます。"
            "旅行者同士の待ち合わせには相互の承諾が必要で、本人確認は安全を保証しません。"
        ),
        "place.summary": (
            "{name} — カタログ推定 {currency} {price}／人、約 {minutes} 分、体力レベル "
            "5 段階中 {effort}。"
        ),
        "place.hours_recorded": (
            "記録されている営業時間: {hours}。これはカタログデータで、ライブ配信では"
            "ありません。"
        ),
        "place.hours_missing": "営業時間が記録されていないため、確認できません。",
        "place.stepfree": "段差のないアクセスがカタログに記録されています。",
        "place.access_unknown": (
            "車いすでのアクセス性は不明です。推測はしません。"
        ),
        "place.access_barriers": (
            "このアクティビティにはアクセシビリティ上の障壁がカタログに記録されています。"
        ),
        "place.reports_signal": (
            "最新の旅行者シグナル: {category} — {source}、鮮度 {freshness}。"
        ),
        "place.reports_none": "この場所に関する最近の旅行者報告はありません。",
        "place.limit_availability": (
            "リアルタイムの空き状況・チケット・待ち時間APIは設定されていません。"
        ),
        "place.limit_catalog": (
            "価格と時間はカタログ記録によるもので、古い可能性があります。"
        ),
        "clarify.ask": (
            "どの日またはどのアクティビティのことですか？旅行中に旅程が変わり得るため、"
            "推測せずにお尋ねします。"
        ),
        "language.note_mixed": (
            "メッセージに {mixed} と {language} が混在していました。最も確信のある言語で"
            "回答しました。どちらの言語でも再度お尋ねください。"
        ),
        "language.note_unsupported": (
            "{script} を検出しましたが、まだその言語では回答できません。回答は英語・"
            "スペイン語・フランス語・ドイツ語・ポルトガル語・イタリア語・ヒンディー語・"
            "日本語で利用できるため、この回答は {language} です。"
        ),
        "language.note_unknown": (
            "言語を確信をもって特定できなかったため、{language} で回答しました。言語を"
            "明示的に選ぶこともできます。"
        ),
        "language.limit": (
            "この回答は SAFAR の記録からローカルで生成されたテンプレートであり、人や"
            "モデルによる翻訳ではありません。"
        ),
        "action.itinerary": "旅程を開く",
        "action.engine": "Group Engine を開く",
        "action.expenses": "費用を開く",
        "action.members": "メンバーを開く",
        "action.voting": "投票を開く",
        "action.privacy": "プライバシー設定を開く",
        "action.rescue": "Trip Rescue を開く",
        "action.evidence": "意思決定エビデンス・パスポートを開く",
        "action.overview": "旅行の概要を開く",
        "action.review": "推薦を確認する",
        "action.open_trip": "旅行を開く",
        "limit.no_llm": "外部LLMもライブ旅行APIも設定されていません。",
        "limit.trip_data": "この回答は SAFAR の旅行記録のみを使用しています。",
        "role.owner": "オーナー",
        "role.admin": "管理者",
        "role.member": "メンバー",
        "role.guest": "ゲスト",
    },
}


def t(key: str, lang: str, **values) -> str:
    """Look up a template in the requested language, falling back to English."""
    catalogue = TEXTS.get(lang)
    template = None
    if catalogue is not None:
        template = catalogue.get(key)
    if template is None:
        template = TEXTS["en"].get(key)
    if template is None:
        return key
    if not values:
        return template
    try:
        return template.format(**values)
    except (KeyError, IndexError, ValueError):
        return template
