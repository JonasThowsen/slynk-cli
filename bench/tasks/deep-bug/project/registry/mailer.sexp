(:package "mailer"
 :description "Composes and sends mail over SMTP."
 :releases
 ((:version "2.2.0" :published "2025-04-17"
    :dependencies (("mime-types" "~2.1.4") ("smtp" "^0.3.0") ("base64" "^1.0.0") ("logging" "^2.0.0")))
  (:version "2.1.0" :published "2024-09-09"
    :dependencies (("mime-types" "~2.1.4") ("smtp" "^0.3.0") ("base64" "^1.0.0")))
  (:version "2.0.0" :published "2024-01-15"
    :dependencies (("mime-types" "^2.0.0") ("smtp" "^0.3.0") ("base64" "^1.0.0")))))
