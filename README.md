# PIMPON — Android

Application Android native en Kotlin/Jetpack Compose, adaptée au parcours de l’application iOS de la branche `SWIFT`.

## Lancer

1. Ouvrir le dossier dans Android Studio et laisser Gradle synchroniser.
2. Lancer la configuration `app` sur un appareil ou un émulateur Android.
3. La simulation démarre par défaut et fonctionne sans carte ESP32 ni réseau.

L’interface propose un rôle **Admin** pour préparer la maquette et déclencher un faux appel, et un rôle **Pompier** avec appel entrant, réponse, départ, commandes de conduite, arrivée, pompe, extinction et fin. Les cartes affichent séparément leurs connexions, erreurs et sorties confirmées. Les commandes en attente ou refusées restent distinctes des sorties appliquées.

## Simulation et matériel

La liaison Admin/Pompier utilise un relais WebSocket local : ouvrez le relais dans l’écran Admin, puis saisissez l’adresse affichée dans l’écran Pompier. Les deux téléphones doivent rester sur le même Wi‑Fi et l’application Pompier doit rester ouverte. L’admin reçoit les mises à jour de l’étape, de la présence sur zone, de la pompe et du feu simulé. Pour tester un seul téléphone, utilisez « Tester le scénario sur ce téléphone ».

Dans l’écran Admin, choisissez `Simulation` ou `Matériel`. En mode Matériel, configurez les deux adresses WebSocket des ESP32. La simulation fournit les outils pour simuler l’arrivée et la perte de connexion.

Le contrat JSON proposé et les limites de sécurité sont décrits dans [`PROTOCOL.md`](PROTOCOL.md). Le déplacement depuis l’application requiert les commandes `drive` et `stopDrive` dans le firmware camion; elles ne sont pas encore présentes sur les ESP32. La simulation les prend en charge. Ne testez pas le déplacement réel avant d’ajouter et de valider ces commandes et un arrêt matériel. La pompe est bloquée hors zone, et son activation ne prouve ni débit d’eau ni extinction.

Le niveau d’eau n’est pas mesuré. La température est informative uniquement lorsqu’une valeur est fournie par la carte et ne décide jamais de l’extinction.

## Compilation

```powershell
.\gradlew.bat :app:assembleDebug
```
