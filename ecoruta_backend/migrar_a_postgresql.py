import os
import sys
import subprocess
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent

def main():
    print("=" * 60)
    print("🚀 SCRIPT DE MIGRACIÓN DE SQLITE A POSTGRESQL - ECORUTA")
    print("=" * 60)
    
    python_bin = sys.executable
    backup_file = BASE_DIR / "datos_sqlite_backup.json"

    # Step 1: Dump data from SQLite
    print("\n📦 1. Exportando datos actuales de SQLite...")
    env_sqlite = os.environ.copy()
    env_sqlite["USE_POSTGRES"] = "False"

    res = subprocess.run([
        python_bin, "manage.py", "dumpdata",
        "--natural-foreign", "--natural-primary",
        "-e", "contenttypes", "-e", "auth.Permission",
        "--indent", "2", "-o", str(backup_file)
    ], cwd=BASE_DIR, env=env_sqlite)

    if res.returncode == 0:
        print(f"✅ Copia de seguridad guardada en: {backup_file}")
    else:
        print("❌ Error al exportar datos de SQLite.")
        return

    # Step 2: Migrate to PostgreSQL
    print("\n🗄️ 2. Conectando con PostgreSQL y aplicando estructura...")
    env_pg = os.environ.copy()
    env_pg["USE_POSTGRES"] = "True"
    
    # Custom credentials if provided in command line
    if len(sys.argv) >= 2:
        env_pg["DB_NAME"] = sys.argv[1]
    if len(sys.argv) >= 3:
        env_pg["DB_USER"] = sys.argv[2]
    if len(sys.argv) >= 4:
        env_pg["DB_PASSWORD"] = sys.argv[3]
    if len(sys.argv) >= 5:
        env_pg["DB_HOST"] = sys.argv[4]

    res_mig = subprocess.run([python_bin, "manage.py", "migrate"], cwd=BASE_DIR, env=env_pg)
    if res_mig.returncode != 0:
        print("\n❌ No se pudo conectar o migrar en PostgreSQL. Verifica que el servicio de PostgreSQL esté activo.")
        print("💡 Nota: Puedes activar PostgreSQL pasando tus credenciales así:")
        print("   python migrar_a_postgresql.py <nombre_bd> <usuario> <contraseña> <host>")
        return

    # Step 3: Load data to PostgreSQL
    print("\n📥 3. Cargando datos exportados en PostgreSQL...")
    res_load = subprocess.run([python_bin, "manage.py", "loaddata", str(backup_file)], cwd=BASE_DIR, env=env_pg)
    if res_load.returncode == 0:
        print("\n🎉 ¡MIGRACIÓN COMPLETADA CON ÉXITO A POSTGRESQL!")
        print("Para ejecutar el servidor con PostgreSQL usa:")
        print("   $env:USE_POSTGRES='True'; ..\\venv\\Scripts\\python.exe manage.py runserver 0.0.0.0:8000")
    else:
        print("⚠️ Se crearon las tablas en PostgreSQL pero hubo un aviso cargando datos.")

if __name__ == "__main__":
    main()
