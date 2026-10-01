# Crée (ou met à jour) les contrôles de la stack dans Healthchecks.
# Idempotent : relançable sans rien dupliquer. Exécuté par `make healthchecks-init` :
#   docker exec -i -e ... healthchecks ./manage.py shell < mnt/healthchecks/init_checks.py
#
# Variables : HC_OWNER_EMAIL (compte transmis par tinyauth), HC_PING_KEY (optionnelle),
# HC_BACKUP_CRON / HC_CHECK_CRON (plannings Restic), HC_TZ.
import os
from datetime import timedelta

from django.contrib.auth.models import User

from hc.accounts.views import _make_user
from hc.api.models import Check

email = os.environ["HC_OWNER_EMAIL"]
tz = os.environ.get("HC_TZ", "Europe/Paris")

user = User.objects.filter(email=email).first()
if user is None:
    user = _make_user(email, tz=tz)
    # Contrôle de démonstration créé avec chaque nouveau compte
    Check.objects.filter(project__owner=user, slug="my-first-check").delete()

project = user.project_set.first()
project.name = "Docker Master"
wanted_key = os.environ.get("HC_PING_KEY") or None
if wanted_key:
    project.ping_key = wanted_key
elif not project.ping_key:
    project.set_ping_key()
project.save()

CHECKS = [
    {
        "slug": "restic-backup",
        "name": "Sauvegarde Restic",
        "desc": "backup.sh du conteneur restic : dump MariaDB, données Portainer, exports Oracle.",
        "schedule": os.environ.get("HC_BACKUP_CRON", "30 12 * * *"),
        # Laisse le temps à la sauvegarde de finir, et à la VM WSL d'être allumée
        "grace": timedelta(hours=2),
    },
    {
        "slug": "restic-check",
        "name": "Vérification du dépôt Restic",
        "desc": "check.sh du conteneur restic : restic check hebdomadaire.",
        "schedule": os.environ.get("HC_CHECK_CRON", "0 13 * * 1"),
        "grace": timedelta(hours=2),
    },
]

for spec in CHECKS:
    check, created = Check.objects.get_or_create(project=project, slug=spec["slug"])
    check.name = spec["name"]
    check.desc = spec["desc"]
    check.kind = "cron"
    check.schedule = spec["schedule"]
    check.tz = tz
    check.grace = spec["grace"]
    check.save()
    check.assign_all_channels()
    print(("créé" if created else "mis à jour"), spec["slug"], spec["schedule"], tz)

print(f"PING_KEY={project.ping_key}")
