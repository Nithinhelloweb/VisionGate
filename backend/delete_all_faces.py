import os
import pg_adapter

cursor = pg_adapter.cursor

def delete_all_faces():
    try:
        cursor.execute("SELECT reg_no, name, role, embedding IS NOT NULL as has_face FROM users")
        users = cursor.fetchall()

        print(f"Found {len(users)} users in database:")
        users_with_faces = 0
        for user in users:
            reg_no, name, role, has_face = user
            if has_face:
                users_with_faces += 1
                print(f"  - {reg_no} ({name}, {role}): HAS face data")
            else:
                print(f"  - {reg_no} ({name}, {role}): NO face data")

        print(f"\nTotal: {len(users)} users, {users_with_faces} with face data")

        print("\nDeleting all face embeddings...")
        cursor.execute("UPDATE users SET embedding = NULL")
        cursor.execute("SELECT COUNT(*) FROM users WHERE embedding IS NOT NULL")
        remaining = cursor.fetchone()[0]

        print(f"Deleted face data for {users_with_faces} users")
        print(f"Remaining users with face data: {remaining}")

        print("\nAll face embeddings have been deleted successfully!")
        print("Users will need to re-register their faces using the app.")

        return True

    except Exception as e:
        print(f"Error: {e}")
        return False

if __name__ == "__main__":
    delete_all_faces()
