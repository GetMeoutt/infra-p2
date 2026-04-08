from flask import Flask, request, jsonify
import mysql.connector
import bcrypt
import jwt
import os
from datetime import datetime, timedelta

app = Flask(__name__)
SECRET_KEY = os.environ.get('SECRET_KEY', 'dev-secret')

def get_db():
    return mysql.connector.connect(
        host=os.environ.get('MYSQL_HOST', 'localhost'),
        database=os.environ.get('MYSQL_DB', 'videodb'),
        user=os.environ.get('MYSQL_USER', 'root'),
        password=os.environ.get('MYSQL_PASSWORD', '')
    )

@app.route('/health')
def health():
    return jsonify({'status': 'ok'})

@app.route('/register', methods=['POST'])
def register():
    data = request.get_json()
    username = data.get('username', '').strip()
    email = data.get('email', '').strip()
    password = data.get('password', '')

    if not username or not email or not password:
        return jsonify({'error': 'All fields required'}), 400
    if len(password) < 6:
        return jsonify({'error': 'Password must be at least 6 characters'}), 400

    pw_hash = bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute('INSERT INTO users (username, email, password_hash) VALUES (%s, %s, %s)', (username, email, pw_hash))
        conn.commit()
        user_id = cur.lastrowid
        cur.close(); conn.close()
        token = jwt.encode({'user_id': user_id, 'username': username, 'exp': datetime.utcnow() + timedelta(hours=24)}, SECRET_KEY, algorithm='HS256')
        return jsonify({'token': token, 'username': username}), 201
    except mysql.connector.IntegrityError:
        return jsonify({'error': 'Username or email already exists'}), 409
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/login', methods=['POST'])
def login():
    data = request.get_json()
    username = data.get('username', '').strip()
    password = data.get('password', '')
    try:
        conn = get_db()
        cur = conn.cursor(dictionary=True)
        cur.execute('SELECT * FROM users WHERE username=%s OR email=%s', (username, username))
        user = cur.fetchone()
        cur.close(); conn.close()
        if not user or not bcrypt.checkpw(password.encode(), user['password_hash'].encode()):
            return jsonify({'error': 'Invalid credentials'}), 401
        token = jwt.encode({'user_id': user['id'], 'username': user['username'], 'exp': datetime.utcnow() + timedelta(hours=24)}, SECRET_KEY, algorithm='HS256')
        return jsonify({'token': token, 'username': user['username'], 'user_id': user['id']})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/validate', methods=['POST'])
def validate():
    token = request.get_json().get('token', '')
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=['HS256'])
        return jsonify({'valid': True, 'user_id': payload['user_id'], 'username': payload['username']})
    except jwt.ExpiredSignatureError:
        return jsonify({'valid': False, 'error': 'Token expired'}), 401
    except jwt.InvalidTokenError:
        return jsonify({'valid': False, 'error': 'Invalid token'}), 401

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001)
