# Rapport de Stress Test - TeamSpeak Docker Cloud

> Genere le 29/10/2026 a 15:14:09

## Architecture testee
| Replica | Container | CPU limit | Condition |
|---|---|---|---|
| R1 | webserver_app | 0.25 | Container de base (compose) |
| R2 | webserver_r2 | 0.45 | Spawne si CPU R1 > 60% |
| R3 | webserver_r3 | 0.65 | Spawne si CPU R2 > 60% |
| Stop | R3 stoppe | - | Si CPU R3 > 80% |


---
## VERIFICATION PREREQUIS
[15:14:09] Container webserver_app actif.
[15:14:09] API Flask accessible : /api/health -> 200 en 94ms
[15:14:10] Image webserver detectee : tp1-webserver

---
## PHASE 1 - REPLICA 1 (CPU 0.25) - Tests TS3 de base

| Etat | Test | Resultat |
|---|---|---|
[15:14:10] T1.1 - Baseline /api/health x10 sequentiel
| OK | T1.1 /api/health x10 | avg=22ms | max=26ms | erreurs=0 |
[15:14:10] T1.2 - ServerQuery serverinfo via /api/stats x10
| OK | T1.2 /api/stats (serverinfo) | avg=30ms | max=46ms | erreurs=0 |
[15:14:12] T1.3 - ServerQuery channellist via /api/channels x10
| OK | T1.3 /api/channels (channellist) | avg=28ms | erreurs=0 |
[15:14:15] T1.4 - ServerQuery N+1 clientinfo via /api/users x10 sequentiel
| OK | T1.4 /api/users (N+1 ServerQuery) | avg=29ms | max=74ms | erreurs=0 |
[15:14:18] UDP TS3 port 9987 : envoi 25 paquets 512B (phase P1)
| OK | T1.5 UDP port 9987 (voix TS3 - 1 client) | 25 paquets 512B | erreurs=0 |
[15:14:22] T1.6 - CPU webserver_app apres Phase 1 : 0.49%
| INFO | T1.6 CPU Replica 1 | 0.49% (seuil scale-up: 60%) |

---
## DECISION AUTO-SCALING -> REPLICA 2
[15:14:22] CPU R1 = 0.49% < 60% - Pas de scaling automatique.
[15:14:22] Spawn R2 force pour le test de charge.
**Decision** : CPU R1 = 0.49% < 60% - Spawn R2 force pour test.
[15:14:22] Scale-UP horizontal : spawn webserver_r2 (CPU limit 0.45)
[15:14:27] Replica webserver_r2 demarre : True

---
## PHASE 2 - REPLICA 2 (CPU 0.45) - Stress ServerQuery modere

| Etat | Test | Resultat |
|---|---|---|
[15:14:27] T2.1 - ServerQuery flooding : 10 appels /api/users en parallele
| OK | T2.1 /api/users x10 parallele (flood ServerQuery) | avg=154ms | max=240ms | OK=10/10 | erreurs=0 |
[15:14:30] T2.2 - Dashboard refresh x10 : stats + channels + users + logs
| OK | T2.2 Dashboard refresh x10 (40 appels TS3) | avg=32ms | erreurs=0 |
[15:14:32] UDP TS3 port 9987 : envoi 50 paquets 512B (phase P2)
| OK | T2.3 UDP port 9987 (voix TS3 - 2 clients) | 50 paquets 512B | erreurs=0 |
[15:14:38] T2.4 - CPU webserver_r2 apres Phase 2 : 0.47%
| INFO | T2.4 CPU Replica 2 | 0.47% (seuil scale-up: 60%) |

---
## DECISION AUTO-SCALING -> REPLICA 3
[15:14:38] CPU R2 = 0.47% < 60% - Spawn R3 force pour saturation max.
**Decision** : CPU R2 = 0.47% < 60% - Spawn R3 force.
[15:14:38] Scale-UP horizontal : spawn webserver_r3 (CPU limit 0.65)
[15:14:42] Replica webserver_r3 demarre : True

---
## PHASE 3 - REPLICA 3 (CPU 0.65) - Stress max + monitor saturation

| Etat | Test | Resultat |
|---|---|---|
[15:14:42] T3.1 - ServerQuery flooding intensif : 20 appels /api/users en parallele
| OK | T3.1 /api/users x20 parallele (ServerQuery sature) | avg=150ms | max=210ms | OK=20/20 | erreurs=0 |
[15:14:46] T3.2 - Dashboard refresh rapide x20 : stats + channels + users + logs
| OK | T3.2 Dashboard rapide x20 (80 appels TS3) | avg=30ms | erreurs=0 |
[15:14:50] UDP TS3 port 9987 : envoi 200 paquets 512B (phase P3)
| OK | T3.3 UDP port 9987 intensif (8 clients vocaux) | 200 paquets 512B | erreurs=0 |
[15:14:56] T3.4 - Monitor CPU R3 toutes les 2s (10 lectures max)
[15:14:58]   Lecture 1/10 - CPU webserver_r3 : 0.55%
[15:15:01]   Lecture 2/10 - CPU webserver_r3 : 0.55%
[15:15:04]   Lecture 3/10 - CPU webserver_r3 : 0.47%
[15:15:07]   Lecture 4/10 - CPU webserver_r3 : 0.52%
[15:15:10]   Lecture 5/10 - CPU webserver_r3 : 0.54%
[15:15:13]   Lecture 6/10 - CPU webserver_r3 : 0.54%
[15:15:17]   Lecture 7/10 - CPU webserver_r3 : 0.45%
[15:15:20]   Lecture 8/10 - CPU webserver_r3 : 0.48%
[15:15:23]   Lecture 9/10 - CPU webserver_r3 : 0.53%
[15:15:27]   Lecture 10/10 - CPU webserver_r3 : 0.44%
[15:15:29] CPU max R3 : 0.55% - Seuil 80% non atteint.
| OK | T3.4 Monitor CPU R3 | CPU max = 0.55% - Seuil 80% non atteint |

---
## NETTOYAGE
[15:15:29] Scale-DOWN : arret webserver_r3 (SIGTERM)
[15:15:30] Scale-DOWN : arret webserver_r2 (SIGTERM)
[15:15:31] Nettoyage termine. Seul webserver_app reste actif.

---
## Resume

| Replica | CPU limit | CPU max mesure | Saturation |
|---|---|---|---|
| R1 (webserver_app) | 0.25 | 0.49% | Non |
| R2 (webserver_r2) | 0.45 | 0.47% | Non |
| R3 (webserver_r3) | 0.65 | 0.55% | Non |

**Duree totale :** 82s

### Vecteurs de saturation testes (TeamSpeak uniquement)
- **ServerQuery TCP port 10011** : flood /api/users (N+1 clientinfo)
- **Dashboard refresh** : stats + channels + users + logs
- **UDP voix port 9987** : simulation clients vocaux codec OPUS

### Auto-scaling horizontal
- Spawn de nouveaux containers si CPU > 60%
- Stop automatique replica 3 si CPU > 80%
