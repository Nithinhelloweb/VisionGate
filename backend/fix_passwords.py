import bcrypt
import pg_adapter

cursor = pg_adapter.cursor

password = 'admin123'
salt = bcrypt.gensalt()
hashed = bcrypt.hashpw(password.encode('utf-8'), salt)
hashed_str = hashed.decode('utf-8')
print('Generated hash:', hashed_str)

result = bcrypt.checkpw(password.encode('utf-8'), hashed)
print('Verification:', result)

cursor.execute("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'")
tables = cursor.fetchall()
print('Tables:', [t[0] for t in tables])

for table in tables:
    print(f'Found table: {table[0]}')
    if table[0] == 'users':
        cursor.execute('SELECT * FROM users')
        users = cursor.fetchall()
        print(f'Found {len(users)} users')
        if users:
            print(f'First user: {users[0]}')
            cursor.execute('UPDATE users SET password_hash = %s', (hashed_str,))
            print('Updated passwords')
