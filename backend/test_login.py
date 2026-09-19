import bcrypt
import pg_adapter

cursor = pg_adapter.cursor

cursor.execute('SELECT username, password_hash FROM users')
rows = cursor.fetchall()
print('Users in database:')
for row in rows:
    print(f'  {row[0]}: {row[1][:40]}...')

    password = 'admin123'
    try:
        result = bcrypt.checkpw(password.encode('utf-8'), row[1].encode('utf-8'))
        print(f'    Verification for {row[0]}: {result}')
    except Exception as e:
        print(f'    Error for {row[0]}: {e}')
