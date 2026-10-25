(in-package #:trove)

;;; The vocabulary of the sample archive (see sample.lisp): the words of
;;; the desks of a regional newspaper, and the common words around them.
;;; Nouns and verbs are inflected as the articles are written, so that
;;; the stemmer has work to do.

(defparameter *desks*
  '((:harbour
     "harbour" "port" "ship" "ferry" "crane" "quay" "container" "cargo" "dock" "pier"
     "tanker" "fishing" "trawler" "boat" "crew" "captain" "tide" "berth" "shipyard" "freight"
     "lighthouse" "coast" "island" "anchor" "vessel" "pilot" "warehouse" "terminal" "salmon"
     "net" "catch" "fleet" "harbourmaster" "jetty" "tugboat")
    (:weather
     "storm" "rain" "snow" "wind" "flood" "frost" "forecast" "temperature" "gale" "drought"
     "thunder" "lightning" "hail" "fog" "sunshine" "heatwave" "avalanche" "warning" "record"
     "climate" "degree" "season" "winter" "summer" "autumn" "spring" "ice" "cloud" "shower"
     "landslide")
    (:council
     "council" "mayor" "budget" "vote" "election" "party" "candidate" "committee" "tax"
     "policy" "minister" "parliament" "debate" "proposal" "referendum" "coalition" "opposition"
     "municipality" "county" "plan" "hearing" "decision" "majority" "representative" "law"
     "regulation" "permit" "zoning" "spending" "deficit")
    (:sport
     "football" "match" "goal" "league" "team" "player" "coach" "stadium" "season" "cup"
     "final" "skiing" "race" "medal" "champion" "tournament" "referee" "striker" "keeper"
     "victory" "defeat" "transfer" "training" "athlete" "relay" "marathon" "handball"
     "supporter" "trophy" "derby")
    (:business
     "company" "market" "share" "profit" "loss" "bank" "loan" "interest" "investment"
     "investor" "factory" "worker" "union" "strike" "salary" "price" "inflation" "export"
     "import" "contract" "startup" "merger" "shop" "retailer" "customer" "revenue" "growth"
     "bankruptcy" "dividend" "employer")
    (:culture
     "festival" "concert" "theatre" "museum" "exhibition" "artist" "painter" "novel" "author"
     "poet" "film" "director" "actor" "singer" "band" "album" "choir" "gallery" "library"
     "premiere" "orchestra" "stage" "audience" "ticket" "review" "sculpture" "dancer" "opera"
     "comedy" "poem")
    (:health
     "hospital" "doctor" "nurse" "patient" "clinic" "surgery" "treatment" "vaccine" "virus"
     "disease" "medicine" "ambulance" "emergency" "waiting" "diagnosis" "therapy" "health"
     "care" "elderly" "infection" "pharmacy" "operation" "cancer" "heart" "research" "study"
     "trial" "symptom" "dentist" "midwife")
    (:transport
     "road" "bridge" "tunnel" "railway" "train" "bus" "station" "traffic" "accident" "driver"
     "motorway" "airport" "flight" "toll" "cyclist" "pedestrian" "junction" "roadwork" "delay"
     "timetable" "passenger" "tram" "parking" "lorry" "route" "crossing" "speed" "camera"
     "bicycle" "carriage")
    (:school
     "school" "pupil" "teacher" "student" "university" "exam" "lesson" "classroom" "headmaster"
     "kindergarten" "curriculum" "grade" "homework" "lecture" "professor" "campus" "degree"
     "scholarship" "dormitory" "playground" "reading" "mathematics" "language" "graduation"
     "semester" "faculty" "tuition" "library" "course" "textbook")
    (:police
     "police" "court" "judge" "trial" "theft" "burglary" "fraud" "arrest" "suspect" "witness"
     "prison" "sentence" "lawyer" "prosecutor" "investigation" "fine" "robbery" "assault"
     "verdict" "appeal" "officer" "patrol" "crime" "victim" "evidence" "charge" "custody"
     "detective" "smuggling" "vandalism")
    (:nature
     "forest" "river" "lake" "mountain" "valley" "wolf" "bear" "moose" "reindeer" "bird"
     "eagle" "fish" "salmon" "trail" "hiking" "national" "park" "glacier" "wetland" "species"
     "pollution" "recycling" "waste" "energy" "turbine" "solar" "emission" "carbon" "habitat"
     "conservation")
    (:technology
     "software" "computer" "internet" "network" "data" "phone" "app" "server" "cable" "robot"
     "satellite" "battery" "chip" "website" "hacker" "password" "privacy" "algorithm"
     "broadband" "screen" "camera" "sensor" "drone" "platform" "update" "engineer" "laboratory"
     "invention" "patent" "startup")
    (:food
     "restaurant" "chef" "kitchen" "bakery" "bread" "cheese" "coffee" "market" "harvest"
     "farmer" "farm" "potato" "apple" "berry" "milk" "beer" "wine" "menu" "recipe" "dinner"
     "breakfast" "lunch" "cafe" "butcher" "grocer" "orchard" "festival" "lamb" "cod" "herring"))
  "The desks of the sample newspaper, each with the nouns its articles use.")

(defparameter *verbs*
  '("open" "close" "build" "plan" "cut" "raise" "lower" "win" "lose" "sign" "reject"
    "approve" "delay" "cancel" "start" "end" "warn" "report" "find" "expect" "promise"
    "demand" "protest" "celebrate" "remember" "announce" "launch" "test" "visit" "move"
    "change" "grow" "fall" "rise" "repair" "replace" "remove" "return" "decide" "discuss"
    "investigate" "arrest" "charge" "release" "save" "rescue" "help" "support" "attack"
    "defend" "score" "beat" "train" "hire" "fire" "pay" "charge" "sell" "buy" "invest"
    "export" "import" "produce" "deliver" "connect" "disconnect" "flood" "freeze" "melt"
    "shut" "block" "clear" "inspect" "measure" "count" "estimate" "predict" "publish"
    "perform" "present" "record" "relocate" "restore" "renovate" "expand" "reduce" "increase"
    "prepare" "organize" "complain" "question" "answer" "welcome" "honour" "award" "mark"
    "review" "study" "treat" "operate" "vaccinate" "examine" "teach" "graduate" "travel"
    "arrive" "depart" "land" "sail" "fish" "hunt" "protect" "pollute" "recycle" "generate")
  "Verbs, in their base form.")

(defparameter *adjectives*
  '("new" "old" "big" "small" "local" "national" "regional" "public" "private" "early"
    "late" "high" "low" "long" "short" "major" "minor" "strong" "weak" "young" "senior"
    "final" "first" "last" "next" "annual" "historic" "modern" "popular" "famous" "quiet"
    "busy" "empty" "full" "safe" "dangerous" "cold" "warm" "wet" "dry" "heavy" "light"
    "expensive" "cheap" "free" "open" "closed" "temporary" "permanent" "important" "serious"
    "difficult" "simple" "possible" "unusual" "common" "rare" "rapid" "slow" "sudden"
    "careful" "angry" "happy" "proud" "worried" "surprised" "disappointed" "successful"
    "independent" "international" "northern" "southern" "eastern" "western" "coastal"
    "rural" "urban" "electric" "digital" "traditional" "economic" "political" "cultural"
    "medical" "environmental" "technical" "financial" "legal" "general" "special")
  "Adjectives.")

(defparameter *common-words*
  '("the" "the" "the" "the" "a" "a" "a" "of" "of" "of" "to" "to" "to" "and" "and" "and"
    "in" "in" "in" "on" "on" "for" "for" "with" "with" "at" "by" "from" "after" "before"
    "during" "about" "over" "under" "between" "against" "without" "near" "this" "that"
    "these" "those" "it" "they" "their" "its" "he" "she" "his" "her" "we" "our" "you"
    "is" "are" "was" "were" "has" "have" "had" "will" "would" "can" "could" "should" "may"
    "must" "not" "no" "more" "most" "less" "some" "many" "few" "all" "both" "each" "other"
    "than" "then" "now" "today" "yesterday" "tomorrow" "week" "month" "year" "morning"
    "evening" "night" "day" "time" "people" "resident" "residents" "town" "city" "village"
    "area" "region" "country" "part" "number" "group" "family" "child" "children" "man"
    "woman" "spokesperson" "leader" "chief" "manager" "official" "expert" "according"
    "said" "says" "told" "asked" "also" "still" "already" "again" "only" "very" "just"
    "however" "because" "while" "when" "where" "which" "who" "what" "how" "why" "there"
    "here" "next" "last" "per" "cent" "million" "thousand" "hundred" "kroner" "two" "three"
    "four" "five" "ten" "first" "second" "third" "several" "around" "almost" "least")
  "The words between the others, with the most common ones more than once.")
