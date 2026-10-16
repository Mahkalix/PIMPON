# Protocole ESP32 proposé

Ce contrat reste à implémenter sur les deux ESP32. L’application ne peut pas piloter un firmware qui ne le respecte pas. Le téléphone, le camion et la maison partagent un réseau local ; l’application ouvre deux connexions WebSocket indépendantes. N’exposez pas ces ports sur Internet.

## Connexion et état

À l’ouverture, l’application envoie `getState`. La connexion n’est considérée prête qu’après réception d’un acquittement avec le rôle attendu (`truck` ou `house`) et un état complet. Chaque message de carte doit inclure un numéro `revision` croissant et l’instantané complet des sorties. L’application envoie `{"type":"heartbeat"}` chaque seconde et attend des mises à jour d’état régulières. Une absence d’état pendant cinq secondes met le scénario en pause. Ces délais sont provisoires, pas des limites de sécurité matérielles validées.

Le camion publie `onScene` d’après son capteur. À l’arrivée, l’application arrête la sirène du camion et l’alarme de la maison. En cas de perte de présence, le firmware coupe lui-même la pompe ; l’application la commande aussi à l’arrêt et exige une nouvelle action explicite avant toute réactivation.

## Commandes

```json
{"type":"command","id":"UUID-unique","action":"setPump","payload":{"enabled":true}}
```

```json
{"type":"ack","role":"truck","id":"UUID-unique","success":true,"revision":12,"state":{"emergencyLocked":false,"pumpEnabled":true,"beaconEnabled":false,"sirenEnabled":false,"nozzleAngle":90,"servoStopped":false,"onScene":true,"temperatureCelsius":null}}
```

Actions camion : `getState`, `drive`, `stopDrive`, `setPump`, `setBeacon`, `setSiren`, `setNozzleAngle`, `emergencyStop`, `rearm`.

Actions maison : `getState`, `startFire`, `stopFire`, `setFan`, `setAlarm`, `emergencyStop`, `rearm`.

`drive` reçoit `{"direction":"forward"}`, `reverse`, `left` ou `right`. `stopDrive` immobilise le camion. La carte doit refuser le déplacement quand `onScene` est vrai et couper localement les moteurs à l’arrivée. `emergencyStop` doit arrêter le déplacement, la pompe, les sorties lumineuses et sonores, immobiliser le servo, puis verrouiller les activations. `rearm` n’est accepté qu’une fois les sorties confirmées à l’arrêt.

`startFire` active les LED, le ventilateur et l’alarme. `stopFire` arrête les LED et le ventilateur ; l’alarme est arrêtée avec `setAlarm`.

L’acquittement est envoyé après application de la sortie. Une erreur doit avoir `success:false`, un champ `error` et un état complet. L’application ne traite jamais l’état associé à un refus comme une confirmation de réussite. Une sortie logique appliquée ne prouve ni débit d’eau, ni rotation, ni position mécanique mesurée.

## Sécurité obligatoire côté firmware

- Refuser l’activation de la pompe hors zone et la couper localement dès la perte de présence.
- Arrêter moteurs et sorties lors de l’arrivée, de la perte de heartbeat ou du réseau, puis verrouiller les activations jusqu’au réarmement explicite.
- Fixer et tester une durée maximale locale de pompe après caractérisation du matériel. Cette limite ne constitue pas une confirmation d’extinction.
- Ne jamais restaurer une sortie active au démarrage ou à la reconnexion ; ne pas rejouer les activations restées en attente.
- Valider les rôles, payloads, angles et états de verrouillage de chaque commande.

Les GPIO ne sont pas des alimentations de puissance. Les tensions, courants, broches, circuits et durées de sécurité restent à déterminer sur le montage réel.
