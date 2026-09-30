# Validation de Fire Control

## Parcours simplifié et appel vocal

- Mode, adresses, préférences de notification et de voix et tests de connexion déplacés dans Administration protégée. Orientation et journal retirés de l’interface ; contrôles de pompe et de sécurité conservés.
- Message d’alerte reformulé et lecture française native via AVSpeechSynthesizer, avec texte, Réécouter et Couper le son.
- **Compilation iOS Simulator réussie avec Xcode 16.4.** Contrôle du diff sans erreur. Aucun changement du cœur métier.
- À vérifier sur iPhone : intelligibilité et volume de la voix, répétition/arrêt du message, désactivation dans Administration, interruption lors du départ, de la perte de connexion, de l’arrêt d’urgence et du passage en arrière-plan. Aucun essai audio réel n’est revendiqué.

## Accès Administration par mot de passe

- Accès unique par la petite flamme en haut à droite, champ masqué et mot de passe exact PIMPOM. Reverrouillage à la fermeture et au passage en arrière-plan ; arrêt d’urgence disponible avant authentification.
- Compilation iOS Simulator réussie avec Xcode 16.4. Contrôle du diff sans erreur.
- À vérifier sur iPhone : mot de passe incorrect, casse, annulation, fermeture par glissement, retour d’arrière-plan et accessibilité du champ masqué.

## Refonte compacte de l’interface

- En-tête et connexions simplifiés, illustration retirée, palette graphite/cyan et typographie plus sobre. Aucun changement du scénario, de l’administration ou des notifications.
- **Compilation iOS Simulator réussie avec Xcode 16.4** après cette refonte. Contrôle du diff sans erreur.
- Rendu sur iPhone et contrôles d’accessibilité à vérifier sur cette version ; aucun contrôle visuel exécuté n’est revendiqué.

## Administration et retrait du capteur thermique

- Écran Administration : états et tests séparés pour alarme, ventilateur et LED. Commandes manuelles limitées à la préparation, avec interverrouillage du lancement et du changement de configuration.
- Température retirée de l’interface et du modèle, contrat JSON mis à jour avec la commande `setFireLEDs`.
- **18 tests métier réussis** : les nouveaux tests couvrent les confirmations d’administration, la protection du scénario et de l’arrêt d’urgence, et les trois sorties simulées indépendantes.
- Compilation iOS Simulator avec Xcode 16.4 réussie. Vérification visuelle de la feuille Administration et essais matériels encore à effectuer.

## Style de la capture — 30 septembre 2026

- Thème sombre, flamme vectorielle SwiftUI, hiérarchie typographique et accents orange appliqués à l’interface. Aucun changement de logique métier ni de notification.
- **Compilation iOS Simulator réussie** avec Xcode 16.4 et le SDK iOS 18.5 après la refonte.
- Contrôle visuel sur appareil, VoiceOver et grandes tailles de texte restant à effectuer pour cette version du thème.

## Appel en notification — 30 septembre 2026

- Compilation finale iOS Simulator réussie avec Xcode 16.4 et le SDK iOS 18.5, sans signature.
- **15 tests métier réussis, 0 échec**. Les deux nouveaux tests couvrent l’attente de confirmation du feu, la distinction répondre/accepter, les réponses répétées et le blocage des réponses après déconnexion ou arrêt d’urgence.
- La livraison réelle par `UNUserNotificationCenter` et ses actions système ne sont pas couvertes par ces tests du cœur métier. À vérifier sur iPhone : autorisation et refus, bannière au premier plan, appui prolongé puis Accepter, suppression de l’alerte après réponse ou arrêt d’urgence, notification ancienne après redémarrage, réglages Concentration et mode silencieux.
- Contrôler également la bannière interne avec les grandes tailles de texte et VoiceOver. Aucun test de réception sur iPhone physique n’est revendiqué.

## Mise à jour de l’interface — 30 septembre 2026

- Refonte SwiftUI avec identité secours, composants natifs, états en attente visibles par équipement et réglages dépliables.
- **Compilation iOS Simulator réussie avec Xcode 16.4**, SDK iOS 18.5, destination générique, sans signature. Le projet Xcode et le package local ont été compilés ensemble.
- Contrôle du diff : aucun problème d’espacement.
- Le simulateur iPhone 16e / iOS 18.6 n’a pas terminé son démarrage pendant la vérification : installation, lancement et contrôle visuel non validés. Les vérifications tactiles, VoiceOver, taille de texte et mode sombre restent à effectuer.
- Aucun changement du cœur métier dans cette refonte ; les résultats des 13 tests ci-dessous concernent sa validation initiale.

## Historique : validation initiale du cœur métier

Vérifications exécutées le 30 septembre 2026, avec Swift 6.2.4 et les Command Line Tools sur macOS. **Xcode et le SDK iOS ne sont pas installés dans cet environnement.**

## Résultats obtenus

- Compilation du package `FireControlCore` et de ses tests : réussie.
- **13 tests Swift Testing réussis, 0 échec** (environ 4,3 secondes d’exécution).
- Parcours métier complet avec les deux vrais transports simulés : réussi, du démarrage à la préparation suivante, sans réseau.
- Analyse syntaxique des deux fichiers de l’interface SwiftUI par `swiftc -frontend -parse` : réussie. Cette analyse ne valide pas les types ni les API du SDK iOS.
- `plutil -lint` sur `App/Info.plist` et `FireControl.xcodeproj/project.pbxproj` : réussi.

## Cas automatisés

1. Pompe interdite avant l’arrivée ; demande en attente différente d’une sortie confirmée.
2. Arrivée : arrêt des alarmes une seule fois, feu maintenu, aucune activation de pompe.
3. Arrêt manuel de pompe sans extinction ; échec partiel d’extinction, nouvelle tentative, fin et réarmement.
4. Perte de présence pendant une activation en attente : arrêt prioritaire ; retour sans redémarrage.
5. Déconnexion : pause, état inconnu, reconnexion sans rejeu, reprise explicite avec arrêt confirmé.
6. Arrêt d’urgence : attente des deux cartes et réarmement explicite.
7. Mauvais rôle de carte et acquittement incohérent refusés.
8. Déconnexion de la maison pendant une demande de marche de pompe : demande d’arrêt du camion.
9. Plage de lance contrôlée ; extinction interdite avant utilisation confirmée de la pompe.
10. Confirmation absente : expiration, état inconnu et pause.
11. Instantané ancien incapable de rétablir une ancienne sortie active.
12. Sérialisation JSON et complétude des états par rôle.
13. Parcours complet exécuté sur `SimulationTransport`.

## Reproduire sans Xcode dans cet environnement

Les Command Line Tools contiennent Swift Testing mais ne configurent pas automatiquement son chemin. Leur framework `_Testing_Foundation` ne fournit pas son module Swift ; les tests n’utilisent pas cet overlay. La commande suivante désactive uniquement cet import automatique pour cette exécution, sans modifier le package ni installer de dépendance.

Depuis la racine du dépôt :

```sh
CLANG_MODULE_CACHE_PATH=/tmp/fire-control-clang \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/fire-control-modules \
swift test --package-path SWIFT/FireControl \
  --scratch-path /tmp/fire-control-build \
  --cache-path /tmp/fire-control-cache \
  --disable-sandbox --disable-xctest \
  -Xswiftc -F \
  -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
  -Xlinker -rpath \
  -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks
```

Avec Xcode 16+ sélectionné, commencer par la commande habituelle `swift test` dans le dossier `SWIFT/FireControl`.

## Vérifications restant à effectuer

- Ouvrir le projet dans Xcode, résoudre le package local, compiler avec le SDK iOS et lancer sur simulateur iPhone. **Aucune compilation ni exécution de l’interface iOS n’est revendiquée ici.**
- Parcours tactile complet, rotation, petites tailles d’écran et tailles de texte d’accessibilité.
- Navigation VoiceOver : ordre de lecture, états des commandes, faux appel et arrêt d’urgence.
- Sur iPhone : autorisation réseau local, adresses `ws`/`wss`, pertes Wi-Fi, arrière-plan/suspension et retour au premier plan.
- Avec deux firmwares conformes : échange WebSocket réel, identifiants/rôles, heartbeat, délais, filtrage de présence, arrêt local et absence de reprise automatique.
- Caractérisation physique : plage de servo, durée maximale de pompe, circuits de puissance, détection magnétique et mesures de température. Aucun test électrique ou hydraulique n’a été effectué.
