# Fire Control

Application native iPhone, **iOS 17 minimum**, SwiftUI et Observation (`@Observable`). Le coordinateur et tous les transports s’exécutent sur `MainActor`. Aucune dépendance externe. Le cœur métier est aussi compilable sur macOS 14+ pour ses tests.

## Lancer sur iPhone ou simulateur

1. Installer Xcode 16 ou ultérieur (Swift 6, tests Swift Testing) avec le SDK et un simulateur iOS 17 ou ultérieur.
2. Ouvrir `FireControl.xcodeproj`, sélectionner le schéma partagé **FireControl**, puis un iPhone simulé et lancer avec ⌘R.
3. Pour un iPhone physique, sélectionner une équipe de signature dans Signing & Capabilities et adapter l’identifiant `fr.pimpon.FireControl` si nécessaire.
4. L’application démarre en **Simulation** et connecte deux cartes virtuelles sans réseau. Attendre les deux états « Connecté, état reçu ».

Le projet Xcode utilise le package Swift local `FireControlCore`, situé dans le même dossier. Pas de génération de projet ni de téléchargement de dépendance requis. L’icône utilise pour l’instant l’apparence par défaut : ce livrable est un prototype pédagogique, sans éléments de distribution App Store.

## Démonstration simulée

Remplir physiquement le réservoir avant une démonstration avec eau. L’application ne connaît pas son niveau.

1. **Déclencher l’incendie** : attendre les confirmations maison ; le faux appel apparaît ensuite.
2. **Accepter** l’appel, lire le message puis **Accepter l’intervention**.
3. Attendre les confirmations du gyrophare et de la sirène, puis **Confirmer le départ**. Déplacer le camion avec sa télécommande.
4. **Simuler l’arrivée** : même événement métier que le capteur matériel. Les deux alarmes sont demandées à l’arrêt, le gyrophare et le feu restent actifs.
5. **Activer la pompe** après avoir orienté physiquement la lance pendant la préparation. L’arrêt manuel de la pompe n’éteint pas le feu.
6. Après une activation confirmée, **Confirmer l’extinction**. Attendre l’arrêt confirmé de la pompe, des LED et du ventilateur.
7. **Terminer l’intervention**, attendre tous les arrêts puis **Préparer une nouvelle intervention**.

Les outils de simulation permettent aussi une sortie de zone et des déconnexions séparées. Après une coupure simulée, reconnecter, demander les arrêts si nécessaire puis réarmer. L’arrêt d’urgence verrouille les commandes jusqu’à confirmation des arrêts des deux cartes et réarmement explicite. Les états affichent les confirmations, les demandes en attente et les erreurs ; aucun journal de commandes n’est présenté. Aucune température n’est affichée : le montage ne comporte pas de capteur thermique.

## Interface

Interface de commande sombre et compacte : fond graphite, surfaces planes, séparateurs fins, titres alignés à gauche et accent cyan discret. L’en-tête affiche l’étape réelle et le mode ; les connexions du camion et de la maison tiennent sur deux lignes. Les grandes illustrations, slogans et badges décoratifs ont été retirés pour rapprocher les commandes du haut de l’écran.

Les composants restent natifs SwiftUI : navigation, listes groupées, sélecteur, boutons et sections dépliables. Les états confirmés et les demandes en attente restent explicites. L’arrêt d’urgence est rouge et fixé en bas des écrans actifs. L’utilisateur suit un parcours court : déclencher le feu, accepter l’appel, confirmer le départ, intervenir avec la pompe et confirmer l’extinction. L’orientation et le journal sont absents de l’interface. Les capacités de servo du cœur métier et du protocole restent conservées pour le matériel ; aucune commande de mouvement n’est exposée. Les tailles de texte dynamiques sont prises en charge ; le thème sombre est imposé.

## Appel entrant et notifications iOS

Dans Administration, appuyer sur **Autoriser les notifications d’appel**, puis accepter la demande iOS. Après confirmation du faux feu par la maison, l’application envoie une notification locale « Centre d’alerte — Appel entrant simulé » et affiche une bannière d’appel persistante en haut de l’écran.

- **Accepter** est l’unique action proposée pour l’appel. Elle ouvre le message et lance sa lecture par la synthèse vocale native en français, si activée. Le texte reste visible, avec Réécouter / Couper le son. L’acceptation de l’intervention reste une action distincte. La voix s’arrête en quittant le message, en cas de blocage des commandes ou au passage en arrière-plan.
- Sur la notification iOS, un appui prolongé révèle le bouton **Accepter**. Toucher simplement la notification ouvre l’application ; la fermer n’accepte pas la mission.
- Sans autorisation, la bannière dans l’application permet le même parcours. En cas de refus, un bouton ouvre les réglages de notifications iOS.
- Une sortie de la phase d’appel, une pause ou un arrêt d’urgence retire l’alerte. Les réponses anciennes ou répétées sont ignorées. Après fermeture complète de l’application, une ancienne alerte ne restaure pas l’intervention.

Il s’agit d’une notification locale ordinaire, sans CallKit, PushKit ou appel téléphonique. Son apparence système, son son et sa visibilité dépendent des réglages iOS (notifications, mode silencieux, Concentration). Une notification déjà envoyée peut être visible hors de l’application ; le scénario ne bénéficie d’aucune exécution continue en arrière-plan. En matériel, les sécurités locales des ESP32 restent indispensables. Voir la [documentation Apple sur les actions de notification](https://developer.apple.com/documentation/usernotifications/handling-notifications-and-notification-related-actions).

## Administration de la maison

Appuyer sur la **petite flamme en haut à droite**, puis saisir **PIMPOM** (majuscules) et toucher **Déverrouiller**. Cet accès est le seul point d’entrée vers Administration. Un mot de passe incorrect laisse l’écran verrouillé ; fermer la feuille ou passer l’application en arrière-plan impose une nouvelle saisie. L’écran regroupe le mode Simulation / Matériel, les adresses WebSocket, les préférences de notifications et de voix, les tests de connexion, ainsi que l’alarme de la maison, le ventilateur et les LED du faux feu, avec des boutons Activer / Arrêter et les confirmations séparées. Les commandes de test sont disponibles uniquement en préparation, avec les deux cartes connectées, hors pause et arrêt d’urgence. Remettre les trois sorties à l’arrêt avant de lancer une mission. En intervention, le scénario continue de piloter la maison ; les états restent consultables dans Administration et un résumé reste visible sur la page principale.

L’arrêt d’urgence reste accessible dans cet écran. Le mot de passe est un verrou local de l’interface, pas une authentification du réseau ou des ESP32. Les LED utilisent la nouvelle commande proposée `setFireLEDs`, à implémenter côté ESP32 maison. La simulation prend déjà en charge cette commande. Le montage retenu n’a pas de capteur thermique : la température cible est retirée de l’interface et du modèle. Le [cahier des charges consolidé](../fire-control-spec.md) reprend ce périmètre.

## Organisation

- `App/` : application et vues SwiftUI ; listes défilantes, texte dynamique, contrôles natifs et libellés VoiceOver, cibles d’au moins 44 points. Les états sont décrits en texte, pas uniquement en couleur.
- `Sources/FireControlCore/Models.swift` : états complets, phases et contrat JSON.
- `InterventionCoordinator.swift` : transitions, interverrouillages, confirmations, délais et reprise explicite.
- `Transport.swift` : protocole commun, cartes simulées et deux connexions `URLSessionWebSocketTask`.
- `Tests/FireControlCoreTests/` : tests ciblés du coordinateur, cartes contrôlables pour les erreurs et parcours réel du transport simulé.
- `PROTOCOL.md` : contrat à implémenter sur les ESP32 et exigences de sécurité locales.

## Matériel — avant tout raccordement

Le mode Matériel attend **deux firmwares compatibles avec le contrat proposé**. L’application ne développe pas ces firmwares. Renseigner les deux adresses WebSocket sur un réseau local commun ; accepter l’autorisation réseau local d’iOS. Ne pas utiliser deux points d’accès séparés. Les adresses et la plage configurées restent en mémoire pendant cette session de l’application.

Valider le deuxième ESP32, le capteur magnétique et son filtrage, le montage de l’aimant, le type des deux buzzers, le ventilateur, les LED et leurs circuits, les alimentations de puissance. Le capteur thermique MLX90614 ne fait pas partie du montage retenu. Caractériser la plage de la lance et la durée maximale de pompe. Les GPIO ne sont pas des alimentations de puissance. Aucun brochage ni paramètre électrique n’est supposé ici.

Les firmwares doivent refuser la pompe hors zone, couper localement à la perte de présence ou de heartbeat, limiter sa durée de fonctionnement autonome et rester sûrs après reconnexion. Les délais applicatifs du prototype ne remplacent pas cette caractérisation. La suspension iOS en arrière-plan interrompt potentiellement le heartbeat : la sécurité reste locale sur les ESP32.

## Vérifications

Depuis ce dossier :

```sh
swift test
```

Avec Xcode installé, compilation sans signature pour simulateur :

```sh
xcodebuild -project FireControl.xcodeproj -scheme FireControl \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Pour lancer les tests depuis Xcode, ouvrir également `Package.swift` et choisir le schéma du package `FireControlCore`.

La validation locale et les vérifications restantes sont consignées dans `VALIDATION.md`.
