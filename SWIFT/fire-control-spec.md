# Fire Control : prompt, scénario et fonctionnalités

Version consolidée du 30 septembre 2026. Ce document décrit le périmètre retenu après les ajustements de l’application : natif SwiftUI, interface compacte graphite/cyan, appel à accepter, administration de la maison et absence de capteur thermique.

Documents associés : [lancement et fonctionnement](FireControl/README.md), [contrat JSON détaillé](FireControl/PROTOCOL.md), [résultats de validation et vérifications restantes](FireControl/VALIDATION.md). Les critères ci-dessous sont des exigences ; leur présence ne signifie pas qu’ils ont tous été validés sur iPhone ou sur le matériel.

## 1. Prompt de développement à transmettre à l’agent

Tu es chargé de développer **Fire Control**, une application iOS native en **Swift et SwiftUI**, pour une maquette pédagogique représentant une intervention de pompiers sur un incendie simulé.

### Objectif et périmètre

Construis d’abord une application complète en mode simulation, puis prépare son raccordement à deux ESP32 par Wi-Fi et WebSocket. La voiture est conduite avec sa télécommande physique existante. L’application ne contrôle pas les moteurs et ne doit pas afficher de commandes de conduite.

Le feu est représenté par du papier animé par un ventilateur et éclairé par des LED rouges et oranges. Il n’y a pas de véritable combustion. L’alerte et l’extinction sont scénarisées. Aucun capteur thermique n’est installé : ne prévoir ni température cible, ni mesure simulée, ni affichage « Indisponible » pour la température.

### Architecture matérielle à respecter

- **ESP32 camion** : pompe à eau via module MOSFET, servo SG90 pour orienter la lance sur un axe, gyrophare, sirène, capteur de présence dans la zone d’intervention. Aucun MLX90614 ni autre capteur thermique ne fait partie du montage retenu.
- **ESP32 maison** : commande du ventilateur et des LED du faux feu via des circuits adaptés, et d’un buzzer d’alarme.
- **iPhone** : interface, progression du scénario, faux appel et coordination des deux ESP32.
- **Télécommande physique** : déplacement du camion exclusivement.
- **Réservoir** : rempli physiquement avant la démonstration, sans capteur de niveau. Ne pas afficher de pourcentage, ni inventer de détection d’eau.

### Écrans à réaliser

1. **Préparation** : états de connexion séparés du camion et de la maison, bouton « Déclencher l’incendie » et rappel de préparation du réservoir. Les réglages du mode Simulation / Matériel et des deux adresses WebSocket sont accessibles uniquement dans Administration.
2. **Appel entrant simulé** : bannière persistante en haut de l’application et notification locale iOS « Centre d’alerte — Appel entrant simulé ». Une seule action : **« Accepter »**. Elle ouvre le message, suivi du bouton distinct **« Accepter l’intervention »**. Aucun bouton pour refuser ou passer l’appel. Ne pas utiliser de véritable appel téléphonique, CallKit ou PushKit.
3. **Intervention** : étape en cours, commandes gyrophare et sirène, confirmation de départ, arrivée détectée et commande de pompe. Aucun contrôle d’orientation ni journal de commandes ne doit apparaître dans l’interface. Les états détaillés du camion restent sur la page principale. Un résumé indique si les sorties de la maison sont actives, inconnues, en attente ou confirmées à l’arrêt ; leurs détails sont dans Administration. Aucun affichage de température.
4. **Fin** : intervention terminée, états des équipements, bouton « Préparer une nouvelle intervention ».
5. **Administration de la maison** : écran présenté en feuille, accessible uniquement par la petite flamme en haut à droite, après saisie du mot de passe **PIMPOM** (sensible à la casse). Il regroupe les réglages du mode et des adresses WebSocket, les préférences de notifications et de message vocal, les tests de déconnexion simulée, ainsi que l’alarme de la maison, le ventilateur et les LED du faux feu, avec états, commandes Activer / Arrêter et arrêt d’urgence. Bouton « Fermer » pour revenir à la page principale.

### Direction visuelle et accessibilité

Utilise une interface de commande moderne, sobre et légèrement futuriste : fond graphite, surfaces planes sombres, séparateurs fins et accent cyan discret. Réserve le rouge aux commandes d’arrêt et à la sécurité. Les titres sont alignés à gauche ; la typographie à chasse fixe sert aux petits libellés techniques et aux valeurs, sans envahir les textes de lecture.

L’en-tête compact montre l’étape réelle, le mode et le nombre de cartes connectées. Présente les connexions camion/maison sur deux lignes et place les commandes utiles près du haut de l’écran. N’ajoute ni grande flamme illustrative, ni slogan, ni badge décoratif, ni effet lumineux permanent. La référence visuelle antérieure à grande flamme orange est remplacée par cette direction plus sobre.

Conserve les composants SwiftUI natifs : navigation, listes groupées, boutons, sélecteur de mode et sections de réglages dans Administration. Le journal de commandes et le curseur d’orientation sont retirés de l’interface. Conserve les erreurs et confirmations utiles, avec des textes courts, sans vocabulaire de jeu de rôle. Le thème sombre est imposé. Un arrêt d’urgence reste accessible au bas des écrans actifs, y compris dans Administration.

Prévois des cibles tactiles d’au moins 44 points, des libellés explicites, VoiceOver, les tailles de texte dynamiques et le réglage Réduire les animations. Ne fais dépendre aucun état uniquement de sa couleur. Une commande en attente doit rester identifiable à côté de l’état confirmé précédent.

### Notifications de l’appel simulé

- Dans Administration, proposer « Autoriser les notifications d’appel » ; demander l’autorisation iOS pour les alertes et le son. En cas de refus, proposer l’ouverture des réglages de notifications.
- Envoyer la notification seulement après confirmation des LED, du ventilateur et de l’alarme de la maison. Maintenir la bannière dans l’application pendant l’attente de réponse, même sans autorisation de notifications.
- Après « Accepter », lire un court message du centre d’alerte par synthèse vocale native en français, si cette préférence est activée dans Administration. Afficher aussi le texte et les actions Réécouter / Couper le son. Arrêter la lecture à la sortie du message, au blocage des commandes et au passage en arrière-plan.
- Dans la notification système, l’appui prolongé révèle l’unique action « Accepter ». Cette action ouvre le message d’intervention, sans activer le gyrophare ou la sirène. Leur activation exige ensuite « Accepter l’intervention ».
- Toucher simplement la notification ouvre l’application. La fermer n’accepte pas la mission : les gestes système de fermeture restent possibles.
- Identifier chaque appel pour ignorer les réponses anciennes, répétées ou incompatibles avec l’état courant. Retirer les notifications à la sortie de la phase d’appel, pendant une pause ou après un arrêt d’urgence. Une ancienne notification après fermeture complète de l’application ne doit pas restaurer une intervention.
- Utiliser une notification locale ordinaire via `UserNotifications`. Le son, les bannières et leur visibilité restent soumis aux réglages iOS, au mode silencieux et à Concentration. Aucune exécution continue du scénario en arrière-plan n’est garantie ; une alerte déjà envoyée peut être visible hors de l’application.

### Administration de la maison

L’administration est un espace de réglage local, sans compte, protégé à l’ouverture par un champ de mot de passe masqué. Le mot de passe requis est **PIMPOM**, en majuscules. Une saisie incorrecte affiche une erreur et ne donne accès à aucune commande. Fermer la feuille ou passer l’application en arrière-plan efface la saisie et reverrouille l’accès. Ce verrou local ne constitue pas une authentification des connexions ESP32. L’arrêt d’urgence reste utilisable sans mot de passe, y compris sur l’écran de saisie. Afficher séparément les états confirmés de l’alarme, du ventilateur et des LED, les demandes en attente et les erreurs de la carte maison.

Les tests manuels sont disponibles uniquement en **Préparation**, avec les deux cartes connectées et leurs états reçus, hors pause et hors arrêt d’urgence. Envoyer une seule commande maison à la fois. Les commandes `setAlarm`, `setFan` et `setFireLEDs` agissent indépendamment et ne lancent pas le scénario ni le faux appel.

Avant « Déclencher l’incendie », exiger toutes les sorties confirmées à l’arrêt et aucune commande maison en attente. Bloquer aussi le changement de mode ou l’application de nouvelles adresses pendant une commande maison en attente ou tant qu’une sortie de la maison reste active. En intervention, l’administration reste consultable, mais ses commandes de test sont bloquées : le scénario pilote la maison. L’arrêt d’urgence reste disponible.

### Organisation du code

Sépare les vues SwiftUI, les modèles métier, le coordinateur d’intervention et les transports de communication. Cible iOS 17 minimum et utilise Observation (`@Observable`). Le cœur métier est un package Swift séparé, testable également sur macOS 14+. Le projet et ses tests Swift Testing requièrent Xcode 16 ou ultérieur (outil Swift 6, mode de langage Swift 5). Les mises à jour de l’interface doivent se faire sur le MainActor.

Prévois un protocole de communication commun, une implémentation simulée et une implémentation WebSocket utilisant URLSessionWebSocketTask. Évite les dépendances externes inutiles. Le mode simulation doit fonctionner sans réseau ni ESP32.

Distingue systématiquement : commande demandée, commande en attente, état confirmé et erreur. Une commande envoyée ne constitue pas une preuve que l’équipement a changé d’état. Sans capteur de retour, l’état confirmé signifie que le microcontrôleur a appliqué sa sortie, pas que la pompe projette effectivement de l’eau.

### Règles du scénario

- Le déclenchement démarre le faux feu ; attendre les confirmations du ventilateur, des LED et de l’alarme avant de présenter l’appel et d’envoyer sa notification.
- L’acceptation de l’intervention demande l’activation du gyrophare et de la sirène du camion.
- Le départ est confirmé manuellement. L’arrivée est détectée par un capteur sur le camion : un capteur magnétique sous le véhicule avec un aimant dans la zone est la solution proposée, à valider matériellement. Cette présence ne mesure ni la vitesse ni une position dans toute la rue. L’utilisateur arrête le véhicule avec sa télécommande.
- À la détection stable de l’arrivée, demander automatiquement l’arrêt de la sirène du camion et de l’alarme de la maison, maintenir le gyrophare, et afficher « Camion sur place ». Distinguer les arrêts en attente des arrêts confirmés.
- En simulation, fournir une action clairement identifiée « Simuler l’arrivée » qui produit le même événement que le capteur. Aucun bouton de confirmation manuelle d’arrivée ne remplace le capteur en mode matériel.
- Autoriser la pompe uniquement après l’arrivée et hors arrêt d’urgence.
- Aucune commande d’orientation de la lance n’est exposée dans cette interface. Orienter physiquement la lance avant la démonstration. Le servo et sa plage sûre restent des contraintes du montage et du protocole conservé ; ne pas supposer que toute sa plage mécanique est utilisable.
- Ne prévoir ni chronomètre d’extinction, ni progression en pourcentage, ni extinction automatique liée au temps de fonctionnement de la pompe.
- Pendant l’intervention, le faux feu reste animé et le ventilateur reste actif, même si la pompe fonctionne ou est arrêtée manuellement.
- Afficher « Lorsque vous estimez l’incendie éteint, appuyez sur Confirmer l’extinction ». Cette confirmation est disponible pendant la phase d’intervention, après au moins une activation confirmée de la pompe.
- « Confirmer l’extinction » demande l’arrêt de la pompe, l’extinction des LED et l’arrêt du ventilateur. L’application attend les états confirmés des deux cartes avant d’annoncer « Feu simulé éteint ». En cas d’échec partiel, afficher les équipements encore actifs ou inconnus et permettre de réessayer les commandes d’arrêt.
- Une fois la pompe, le feu et le ventilateur confirmés à l’arrêt, « Terminer l’intervention » demande `emergencyStop` aux deux cartes pour éteindre le gyrophare, immobiliser le servo et confirmer l’arrêt de tous les équipements. Le parcours est terminé après les confirmations des deux cartes. « Préparer une nouvelle intervention » réarme explicitement les deux cartes, sans activer de sortie, puis revient à la préparation.
- Prévoir une limite de durée de marche autonome de la pompe côté firmware, fixée après caractérisation du matériel. Cette limite protège le fonctionnement de la pompe et ne constitue jamais une confirmation d’extinction.
- Si la présence du camion disparaît pendant l’intervention, demander immédiatement l’arrêt de la pompe, bloquer sa réactivation et afficher « Camion hors zone ». À son retour, exiger une nouvelle activation explicite de la pompe. Un faux changement de présence doit être filtré côté firmware.
- Ne pas prévoir de capteur thermique, de champ de température dans le modèle ou de commande associée. La confirmation d’extinction reste une décision utilisateur suivie des arrêts confirmés.

### Connexion et arrêt d’urgence

Les deux ESP32 et l’iPhone doivent être sur un réseau local commun pour la première version matérielle. Prévoir deux connexions WebSocket indépendantes. Ne pas connecter successivement l’iPhone à deux points d’accès séparés pour tenter de commander les deux cartes.

En cas de déconnexion pendant l’intervention, mettre le scénario en pause, désactiver les commandes indisponibles et ne pas annoncer leur exécution. Ne jamais relancer automatiquement la pompe à la reconnexion. Exiger une reprise explicite suivie d’une confirmation d’arrêt de pompe avant de rétablir les commandes. Si une carte est verrouillée par sa sécurité locale, exiger les arrêts confirmés puis un réarmement explicite revenant à la préparation.

L’arrêt d’urgence demande l’arrêt de la pompe, l’arrêt des mouvements du servo, l’arrêt du ventilateur, l’extinction des LED, du gyrophare et des buzzers. Il verrouille les commandes jusqu’à un réarmement explicite. Il ne peut pas arrêter les moteurs de la voiture, commandés par une télécommande indépendante. Afficher cette limite clairement.

Un bouton logiciel seul ne garantit pas l’arrêt si la connexion est coupée : spécifier une temporisation de sécurité locale et un heartbeat dans les firmwares. L’application doit signaler les équipements dont l’arrêt n’a pas été confirmé.

### Livrables et validation

Livre le projet Xcode ouvrable, les sources SwiftUI, un README de lancement, un document de protocole JSON proposé et des tests ciblés sur les transitions, l’interverrouillage de la pompe, la déconnexion et l’arrêt d’urgence, ainsi que sur les réponses à l’appel et les interverrouillages de l’administration. Le protocole doit être présenté comme un contrat à implémenter également sur les ESP32.

Vérifie que le parcours complet fonctionne en simulation, que les actions impossibles sont bloquées, qu’un retour d’erreur ne crée pas un faux état confirmé et que la reprise réseau n’active aucun équipement. Compile et lance sur simulateur iOS si l’environnement le permet. Sinon, indique les vérifications qui restent à effectuer sans prétendre avoir compilé.

Ne développe pas le firmware complet dans cette première étape. Documente les comportements qu’il devra respecter, sans inventer les broches, tensions, bibliothèques ou caractéristiques électriques manquantes.

## 2. Scénario de la démonstration

### Préparation physique

Remplir le réservoir, installer le tuyau et la lance, vérifier les alimentations et placer le camion à son point de départ. Le papier, le ventilateur et l’éclairage représentent le feu. Orienter la projection d’eau vers une zone de réception qui préserve l’électronique.

En mode matériel, connecter les deux ESP32 et vérifier leurs états. En simulation, tous les équipements doivent être identifiés comme simulés. Si nécessaire, tester séparément l’alarme, le ventilateur et les LED dans Administration, puis les remettre à l’arrêt et attendre leurs confirmations. Autoriser les notifications d’appel si l’on souhaite utiliser l’alerte iOS.

### Scène 1 : déclenchement et alerte

L’opérateur appuie sur « Déclencher l’incendie ». L’ESP32 maison active le ventilateur et le clignotement rouge/orange. L’alarme sonore de la maison est activée également.

Après confirmation des sorties de la maison, l’application affiche la bannière d’appel simulé et envoie la notification locale si elle est autorisée. Le pompier appuie sur l’unique bouton « Accepter ». L’application présente alors le message :

> Centre d’alerte. Un départ de feu est signalé dans la maison. Rendez-vous sur place avec le camion, puis utilisez la pompe pour intervenir.

Le pompier appuie ensuite sur « Accepter l’intervention ». L’application demande l’activation du gyrophare et de la sirène du camion et attend leurs confirmations avant d’autoriser le départ.

### Scène 2 : départ

Le pompier confirme le départ dans l’application et conduit la voiture avec sa télécommande. L’application indique « Camion en route » sans prétendre suivre sa position.

### Scène 3 : arrivée

Le pompier positionne et arrête le camion dans la zone prévue avec sa télécommande. Le capteur embarqué détecte la présence de l’aimant de la zone et l’ESP32 camion transmet cet état à l’application.

L’application affiche « Camion sur place », demande automatiquement l’arrêt de la sirène du camion et de l’alarme de la maison, et maintient le gyrophare. Les commandes de lance et de pompe deviennent disponibles, sans activer automatiquement la pompe. Le feu et le ventilateur continuent de fonctionner.

### Scène 4 : intervention et confirmation de l’extinction

La lance a été orientée physiquement pendant la préparation. Le pompier active la pompe. L’eau est projetée vers la zone prévue. Les LED et le ventilateur restent actifs : aucun compte à rebours ne fait diminuer le feu.

L’application affiche : « Lorsque vous estimez l’incendie éteint, appuyez sur Confirmer l’extinction ».

L’utilisateur peut arrêter et redémarrer la pompe pendant l’intervention. Après avoir utilisé la pompe, il appuie sur « Confirmer l’extinction ». Cette action demande simultanément l’arrêt de la pompe sur le camion et l’extinction des LED ainsi que l’arrêt du ventilateur dans la maison. L’application annonce l’extinction seulement après confirmation des sorties concernées. Un arrêt de pompe isolé ne termine pas l’incendie.

### Scène 5 : fin d’intervention

Une fois les arrêts de la pompe et des équipements de la maison confirmés, le pompier appuie sur « Terminer l’intervention ». L’application demande l’arrêt final des deux cartes, dont l’extinction du gyrophare et l’immobilisation du servo. Après confirmation de l’arrêt des équipements, l’application affiche « Intervention terminée ». Le camion peut repartir avec sa télécommande. Une nouvelle intervention nécessite une préparation explicite.

## 3. Fonctionnalités prévues

| Fonctionnalité | Responsable | Information disponible |
| --- | --- | --- |
| Déplacement du camion | Télécommande physique | Aucun pilotage depuis l’application |
| Présence sur les lieux | Capteur embarqué + aimant dans la zone (proposition) | Présence détectée, sans localisation continue ni détection de vitesse |
| Orientation de la lance | Préparation physique du montage ; servo conservé dans le contrat matériel | Aucun curseur ni commande de mouvement dans l’interface utilisateur |
| Pompe marche / arrêt | ESP32 camion + MOSFET | Sortie commandée, sans mesure de débit |
| Gyrophare et sirène | ESP32 camion | État logique des sorties |
| Ventilateur du faux feu | ESP32 maison + circuit adapté | Sortie commandée, sans retour de rotation prévu |
| LED et animation du feu | ESP32 maison + éclairage adapté | Marche / arrêt confirmés ; animation rouge/orange côté firmware, sans réglage d’intensité dans cette version |
| Appel simulé et notification locale | Application + iOS | Alerte scénarisée ; unique action Accepter, puis acceptation distincte de l’intervention |
| Administration de la maison | Application + ESP32 maison | Tests indépendants de l’alarme, du ventilateur et des LED en préparation ; états consultables pendant l’intervention |
| Départ | Utilisateur | Confirmation manuelle |
| Arrêt des alarmes à l’arrivée | Application + deux ESP32 | Sirène du camion et alarme de la maison arrêtées, gyrophare maintenu |
| Confirmation de l’extinction | Utilisateur + application + deux ESP32 | Décision manuelle suivie des arrêts confirmés, sans détection d’eau sur la cible |
| Niveau du réservoir | Aucun capteur prévu | Inconnu |
| Arrêt d’urgence des équipements connectés | Application + firmwares | Confirmation séparée de chaque ESP32 |

## 4. Contrat de communication proposé

Ce contrat est une proposition de développement, pas un protocole déjà disponible sur les cartes. Les détails sont définis dans [PROTOCOL.md](FireControl/PROTOCOL.md). Les exemples ci-dessous utilisent des instantanés complets, conformes au modèle de l’application.

### Connexions

- Camion : adresse WebSocket configurable.
- Maison : adresse WebSocket configurable.
- À la connexion, identifier le rôle de la carte et récupérer un état complet.
- Identifier chaque commande par un UUID unique et exiger une réponse de succès ou d’erreur après application de la sortie. Chaque réponse ou événement inclut `role`, `revision` (entier strictement croissant à chaque émission dans la session) et un `state` complet pour ce rôle. Ne pas remplacer un état récent par un instantané plus ancien ; rejeter une réponse positive dont l’état contredit la commande.
- Émettre un heartbeat applicatif chaque seconde et recevoir un état complet périodique chaque seconde. Le prototype attend au plus 4 secondes un acquittement et 5 secondes un nouvel état ; ce sont des réglages de développement à distinguer des délais de sécurité locaux à caractériser sur le montage.
- L’état camion inclut `onScene`, mis à jour par le capteur. Un événement de changement de présence est envoyé sans attendre une interrogation de l’application.
- Le firmware camion refuse l’activation de la pompe hors zone et coupe localement la pompe si la présence est perdue.
- `startFire` active LED, ventilateur et alarme. `stopFire` éteint les LED et arrête le ventilateur ; la réponse confirme les deux sorties. `setFireLEDs` ne modifie que les LED et leur animation, sans toucher au ventilateur ni à l’alarme.
- Ne pas rejouer les commandes d’activation restées en attente après une reconnexion.

### Commandes par rôle

| Cible | Commandes proposées |
| --- | --- |
| Camion | `setPump`, `setBeacon`, `setSiren`, `setNozzleAngle`, `emergencyStop`, `rearm`, `getState` |
| Maison | `startFire`, `stopFire`, `setFan`, `setFireLEDs`, `setAlarm`, `emergencyStop`, `rearm`, `getState` |

Exemple d’événement d’arrivée émis par le camion :

```json
{
  "type": "event",
  "event": "presenceChanged",
  "role": "truck",
  "revision": 13,
  "state": {
    "emergencyLocked": false,
    "pumpEnabled": false,
    "beaconEnabled": true,
    "sirenEnabled": true,
    "nozzleAngle": 90,
    "servoStopped": true,
    "onScene": true
  }
}
```

À réception pendant la phase de départ, l’application passe à l’arrivée et demande `setSiren` avec `enabled: false` au camion et `setAlarm` avec `enabled: false` à la maison. Un événement répété ne doit pas répéter la transition ou relancer un équipement.

Exemple de commande à destination du camion :

```json
{
  "type": "command",
  "id": "37C13F31-65FD-4B8B-9E67-506C45033CC8",
  "action": "setPump",
  "payload": { "enabled": true }
}
```

Exemple de réponse après application de la sortie :

```json
{
  "type": "ack",
  "id": "37C13F31-65FD-4B8B-9E67-506C45033CC8",
  "success": true,
  "role": "truck",
  "revision": 14,
  "state": {
    "emergencyLocked": false,
    "pumpEnabled": true,
    "beaconEnabled": true,
    "sirenEnabled": false,
    "nozzleAngle": 90,
    "servoStopped": true,
    "onScene": true
  }
}
```

Chaque carte doit refuser les commandes incompatibles avec son rôle, valider les valeurs et respecter son verrouillage d’urgence. Après une coupure de communication, la carte passe localement à un état sûr. Les délais de sécurité locale après perte de heartbeat ou de connexion et la durée maximale autonome de la pompe restent à caractériser et à tester sur le montage. Les réglages applicatifs du prototype ne les remplacent pas.

## 5. Matériel à confirmer avant raccordement

- Ajouter le deuxième ESP32 destiné à la maison.
- Ajouter et valider le dispositif de détection d’arrivée : capteur magnétique sous le camion et aimant dans la zone, comme solution proposée. Vérifier la distance de détection, la compatibilité électrique, la fixation et le filtrage des changements de présence.
- Identifier le ventilateur : tension, courant, connecteurs et éventuelle commande PWM.
- Identifier l’éclairage : LED simples, RGB ou ARGB, et circuit de commande nécessaire. Le RGB du ventilateur ne remplace pas automatiquement des LED rouges/oranges pilotables.
- Vérifier les alimentations et circuits de puissance pour la pompe, le servo et le ventilateur. Les GPIO servent à la commande, pas à leur alimentation directe.
- Confirmer le type du buzzer du camion (actif ou passif) et sa compatibilité avec la sirène prévue ; ne pas déduire son type d’un exemple de code.
- Définir la plage mécanique sûre de la lance et la durée maximale de fonctionnement de la pompe.
- Prévoir le deuxième buzzer pour l’alarme de la maison et confirmer son type.

## 6. Critères d’acceptation de la première version

- Le parcours complet est réalisable en simulation sans matériel.
- Aucun bouton ne prétend conduire la voiture ou connaître le niveau d’eau.
- La pompe est bloquée avant l’arrivée et pendant un arrêt d’urgence.
- La simulation d’arrivée et l’événement du capteur suivent le même parcours métier.
- L’arrivée coupe automatiquement les deux alarmes sans activer la pompe ; le gyrophare et le faux feu restent actifs.
- Aucun chronomètre ni pourcentage ne déclenche l’extinction.
- Un arrêt manuel de la pompe n’éteint pas le feu.
- La confirmation utilisateur demande l’arrêt de la pompe, des LED et du ventilateur ; une erreur partielle empêche l’annonce d’une extinction confirmée.
- Une perte de présence bloque la pompe, sans annoncer une extinction ; le retour en zone ne la réactive pas.
- Les deux connexions et leurs erreurs sont distinguées.
- Les commandes en attente ne sont pas affichées comme confirmées.
- Aucune température n’est affichée ni modélisée : le montage ne comporte pas de capteur thermique.
- L’arrêt d’urgence fonctionne dans la simulation et expose ses limites en mode matériel.
- Une reconnexion ne réactive pas spontanément les équipements.
- Le README explique le lancement, le mode simulation et les prérequis du futur raccordement matériel.
- L’appel n’apparaît qu’après confirmation des trois sorties de démarrage de la maison.
- La bannière et la notification ne proposent que « Accepter » ; cette action ouvre le message sans accepter automatiquement l’intervention.
- Sans autorisation de notifications, le parcours reste réalisable depuis la bannière dans l’application.
- Fermer une notification, la toucher sans sélectionner son action ou utiliser une notification périmée n’accepte pas l’intervention.
- Les réponses répétées, les réponses pendant une pause et celles après arrêt d’urgence ne relancent aucun équipement.
- Administration regroupe l’alarme, le ventilateur et les LED de la maison ; leurs tests manuels sont indépendants et limités à la préparation.
- Une commande d’administration en attente bloque le déclenchement. Une sortie encore active bloque également la nouvelle mission et le changement de configuration de la maison.
- Pendant l’intervention, les commandes manuelles de la maison sont bloquées ; son résumé reste sur la page principale et les états détaillés restent consultables dans Administration.
- L’arrêt d’urgence demeure accessible dans Administration et ne peut pas être contourné par ses commandes.
- L’interface suit la direction graphite/cyan compacte, sans grande illustration ni slogan ; les commandes, notifications et états restent lisibles en grandes tailles de texte et avec VoiceOver.

- La petite flamme est l’unique accès à Administration ; seul le mot de passe exact PIMPOM déverrouille la feuille. Annulation, fermeture et arrière-plan ne doivent laisser aucun accès déverrouillé à la prochaine ouverture.

- Les réglages matériels, les préférences de notification et de voix et les tests de déconnexion sont accessibles uniquement dans Administration ; l’action « Simuler l’arrivée » reste disponible dans le parcours simulé.
- Le parcours utilisateur n’affiche ni orientation de lance ni journal de commandes. Le message vocal reste facultatif et possède une alternative textuelle.
