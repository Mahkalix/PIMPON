# Contrat JSON proposé — Fire Control v1

Ce contrat **reste à implémenter sur les deux ESP32**. L’application ne peut pas piloter un firmware existant qui ne le respecte pas. Aucun firmware complet, brochage, tension ou bibliothèque matérielle n’est fourni.

## Réseau et session

L’iPhone, le camion et la maison partagent un réseau local. Deux WebSocket indépendants sont configurés dans Préparation (`ws://adresse:port` ou `wss://nom:port`). Ce prototype est destiné à un réseau de démonstration de confiance ; il ne fournit pas d’authentification applicative. Ne pas exposer les ports sur Internet. Pour `wss`, utiliser un certificat reconnu par iOS.

À chaque connexion, l’application envoie `getState` avec un UUID neuf. La carte répond avec son rôle et un état complet. La connexion n’est utilisable qu’après cet acquittement. Une carte au mauvais rôle ou un état incomplet provoque la fermeture. Aucun rejeu des activations après reconnexion. Les UUID sont propres à une connexion ; une réponse d’une ancienne connexion n’est pas utilisée.

Chaque message de la carte contient `role` (`truck` ou `house`), `revision` (entier croissant pour **chaque** émission dans la session) et `state` (instantané complet). La révision évite qu’une réponse retardée remplace un état plus récent. Les événements et acquittements utilisent des instantanés complets, comme dans le [cahier des charges consolidé](../fire-control-spec.md), afin de détecter les données manquantes.

## Commandes et acquittements

```json
{"type":"command","id":"UUID-unique","action":"setPump","payload":{"enabled":true}}
```

```json
{
  "type":"ack", "role":"truck", "id":"UUID-unique", "success":true, "revision":12,
  "state":{
    "emergencyLocked":false,
    "pumpEnabled":true, "beaconEnabled":true, "sirenEnabled":false,
    "nozzleAngle":90, "servoStopped":false, "onScene":true
  }
}
```

L’acquittement est émis **après application de la sortie**. Une commande reçue ne suffit pas. Une sortie appliquée ne prouve pas un débit d’eau, une rotation réelle ou une position mécanique mesurée. `servoStopped: true` signifie que le firmware a interrompu toute trajectoire ou évolution de consigne ; la stratégie électrique du servo reste à caractériser.

En cas d’erreur : même enveloppe avec `success:false`, `error:"motif"` et état complet. L’application affiche l’erreur et ne traite pas cet état comme une application réussie de la commande. Un état périodique ultérieur peut actualiser les sorties observées. Un acquittement positif dont l’état contredit l’action est également rejeté.

| Rôle | Action | Payload | Effet confirmé attendu |
| --- | --- | --- | --- |
| Les deux | `getState` | `{}` | Instantané complet, sans activation |
| Camion | `setPump` | `{"enabled":true/false}` | `pumpEnabled` demandé, marche autorisée seulement en zone et hors verrouillage |
| Camion | `setBeacon` | `{"enabled":true/false}` | `beaconEnabled` |
| Camion | `setSiren` | `{"enabled":true/false}` | `sirenEnabled` |
| Camion | `setNozzleAngle` | `{"angle":90}` | Angle appliqué dans la plage validée côté firmware |
| Maison | `startFire` | `{}` | LED animées, ventilateur et alarme actifs |
| Maison | `stopFire` | `{}` | LED et ventilateur arrêtés, alarme indépendante |
| Maison | `setFireLEDs` | `{"enabled":true/false}` | `fireEnabled`, LED uniquement, ventilateur et alarme inchangés |
| Maison | `setFan` | `{"enabled":true/false}` | `fanEnabled` |
| Maison | `setAlarm` | `{"enabled":true/false}` | `alarmEnabled` |
| Les deux | `emergencyStop` | `{}` | Toutes les sorties de cette carte arrêtées, servo immobilisé, verrouillage actif |
| Les deux | `rearm` | `{}` | Déverrouillage, toutes les sorties restent arrêtées |

Les champs des booléens et angles sont obligatoires pour les actions correspondantes. Rejeter les valeurs absentes, non finies, hors plage, les rôles incompatibles et les commandes interdites pendant un verrouillage. La plage 60–120° affichée initialement est un **exemple de simulation**, pas une caractéristique du montage. En matériel, la commande de lance reste bloquée tant que l’utilisateur n’a pas validé sa plage ; le firmware doit imposer sa propre plage sûre.

Traiter les commandes d’une connexion dans l’ordre. Rendre les commandes idempotentes, mémoriser les UUID traités dans la session et répondre sans répéter un mouvement. Un arrêt doit supplanter les activations encore en file ; un arrêt d’urgence verrouille aussi le traitement des activations tardives. `rearm` n’est permis que si les sorties sont arrêtées. Le firmware ne doit jamais restaurer automatiquement des sorties actives au démarrage ou à la reconnexion.

## États et présence

État camion complet : tous les champs de l’exemple d’acquittement. Aucun capteur thermique n’est prévu sur le montage : aucun champ de température n’est utilisé par l’application. Les anciens messages contenant ce champ restent décodables (champ supplémentaire ignoré).

État maison complet :

```json
{"emergencyLocked":false,"fireEnabled":true,"fanEnabled":true,"alarmEnabled":true}
```

Après filtrage matériel de la présence, le camion émet immédiatement :

```json
{
  "type":"event", "event":"presenceChanged", "role":"truck", "revision":13,
  "state":{
    "emergencyLocked":false,"pumpEnabled":false,"beaconEnabled":true,
    "sirenEnabled":true,"nozzleAngle":90,"servoStopped":true,"onScene":true
  }
}
```

La présence ne mesure ni vitesse ni position continue. L’application demande l’arrêt des deux alarmes à la première arrivée pendant le trajet. Un événement répété ne rejoue pas la transition. À la perte de présence, **le firmware coupe immédiatement la pompe**, sans attendre l’iPhone, et l’application envoie aussi une demande d’arrêt. Le retour de présence ne relance rien.

## Heartbeat et sécurité locale à caractériser

L’application émet `{"type":"heartbeat"}` chaque seconde. La carte doit publier chaque seconde un message `{"type":"state","role":"truck|house","revision":N,"state":{...}}`, même si les sorties ne changent pas. Ces messages assurent la surveillance dans les deux sens.

Valeurs du prototype applicatif : délai d’acquittement de 4 secondes, absence d’état tolérée 5 secondes. Ce sont des réglages de développement, **pas des durées de sécurité matérielle validées**. Un dépassement rend les sorties inconnues, ferme la connexion et met le parcours en pause. La reprise exige une action explicite et une confirmation d’arrêt de pompe. Un verrouillage matériel exige l’arrêt confirmé des deux cartes puis un réarmement explicite revenant à la préparation.

Les firmwares doivent avoir une temporisation locale indépendante, choisie et testée sur le montage, pour :

- Perte de heartbeat, fermeture WebSocket, blocage de l’iPhone, mise en arrière-plan : arrêter localement pompe, servo, ventilateur, LED, gyrophare et alarmes selon le rôle, puis verrouiller les activations.
- Durée maximale autonome de marche de la pompe : couper même si le réseau fonctionne. Fixer cette durée après caractérisation de la pompe ; publier immédiatement le nouvel état et le motif. Cette protection **ne confirme jamais l’extinction**.
- Perte de présence : couper localement la pompe et ne jamais réactiver au retour.

La simulation confirme des sorties logiques avec une latence de 180 ms, filtre les commandes interdites et reproduit l’arrêt local lors d’une déconnexion. Elle ne représente ni l’hydraulique ni les contraintes électriques, et ne prétend pas valider les durées de protection du futur firmware.

L’arrêt logiciel ne garantit rien sur une carte déconnectée : l’application affiche alors « inconnu, non confirmé ». Les moteurs de la voiture restent exclusivement sous le contrôle de la télécommande.

## Fin et reprise

L’extinction manuelle demande `setPump(false)` et `stopFire`, puis attend les sorties correspondantes des deux cartes. Les alarmes sont également redemandées à l’arrêt. Une erreur laisse les états visibles et autorise une nouvelle demande d’arrêt.

La fin demande `emergencyStop` aux deux cartes : cela éteint le gyrophare et immobilise aussi le servo. « Intervention terminée » n’est annoncé qu’après confirmation des sorties arrêtées. « Préparer une nouvelle intervention » réarme explicitement les deux cartes sans activer leurs sorties.

## Administration de la maison

Les commandes manuelles `setAlarm`, `setFan` et `setFireLEDs` sont accessibles dans Administration pendant la préparation, hors pause et arrêt d’urgence, après réception des états des deux cartes. Une seule commande maison à la fois ; les sorties affichées ne changent qu’après confirmation. Toutes les sorties doivent être arrêtées et aucune commande maison en attente avant le lancement du scénario ou un changement de configuration. Pendant l’intervention, Administration affiche les états sans permettre de modifier le scénario.

`setFireLEDs` est une extension du contrat proposé : le firmware maison doit l’implémenter pour tester les LED indépendamment. `startFire` et `stopFire` conservent leur rôle de coordination du feu et du ventilateur pendant le scénario. L’écran est protégé par le mot de passe local PIMPOM. Il s’agit uniquement d’un verrou d’interface : le protocole WebSocket ne transmet pas ce mot de passe et n’acquiert pas de mécanisme d’authentification.

## Interface simplifiée

Le mode et les adresses WebSocket se configurent dans Administration, derrière le verrou local. L’interface ne présente plus de journal de commandes ni de contrôle d’orientation. `setNozzleAngle`, `nozzleAngle` et `servoStopped` restent dans le contrat matériel pour compatibilité et sécurité ; la présence de ces champs n’implique pas un curseur dans l’application. Le message vocal d’appel est une synthèse locale iOS, sans commande réseau supplémentaire.
