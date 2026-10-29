#!/bin/sh
# Entrypoint du container lint.
# Lance flake8 (Python) puis eslint (JS/JSX).
# En cas d'échec de l'un ou l'autre, le script retourne un code non-nul
# ce qui est interprété comme un échec en CI.

LINT_EXIT=0

echo "=========================================="
echo "  LINT PYTHON — flake8 + pylint"
echo "=========================================="

if [ -d "/code/backend" ]; then
    echo "[flake8] Analyse du backend Python..."
    flake8 /code/backend --config=/code/.flake8
    FLAKE8_EXIT=$?

    echo ""
    echo "[pylint] Analyse statique du backend Python..."
    # --fail-under=7.0 : le score pylint doit etre >= 7/10
    pylint /code/backend/app.py \
        --disable=C0114,C0115,C0116 \
        --max-line-length=100 \
        --fail-under=7.0 2>/dev/null
    PYLINT_EXIT=$?

    if [ $FLAKE8_EXIT -ne 0 ] || [ $PYLINT_EXIT -ne 0 ]; then
        echo "[FAIL] Lint Python échoué."
        LINT_EXIT=1
    else
        echo "[OK] Lint Python réussi."
    fi
else
    echo "[WARN] Dossier /code/backend introuvable — lint Python ignoré."
fi

echo ""
echo "=========================================="
echo "  LINT JAVASCRIPT — eslint"
echo "=========================================="

if [ -d "/code/frontend" ]; then
    echo "[eslint] Analyse du frontend JS/JSX..."
    # --no-ignore : ne pas utiliser .eslintignore (on veut tout analyser)
    eslint /code/frontend/src --ext .js,.jsx \
        --config /code/eslint.config.mjs \
        --no-ignore 2>/dev/null
    ESLINT_EXIT=$?

    if [ $ESLINT_EXIT -ne 0 ]; then
        echo "[FAIL] Lint JS échoué."
        LINT_EXIT=1
    else
        echo "[OK] Lint JS réussi."
    fi
else
    echo "[WARN] Dossier /code/frontend introuvable — lint JS ignoré."
fi

echo ""
echo "=========================================="
if [ $LINT_EXIT -eq 0 ]; then
    echo "  RÉSULTAT : TOUS LES LINTS PASSENT ✓"
else
    echo "  RÉSULTAT : DES ERREURS ONT ÉTÉ DÉTECTÉES ✗"
fi
echo "=========================================="

exit $LINT_EXIT
