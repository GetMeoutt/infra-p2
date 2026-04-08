"""
Stream Service - Port 5004
Handles: login, browse videos, watch/stream video
Talks to: Auth Service, File Service, MySQL Service
"""
from flask import Flask, render_template, request, redirect, url_for, session, flash, Response
import requests, os, functools

app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY', 'dev-secret')

AUTH = os.environ.get('AUTH_SERVICE_URL', 'http://localhost:5001')
FILES = os.environ.get('FILE_SERVICE_URL', 'http://localhost:5002')
DB = os.environ.get('MYSQL_SERVICE_URL', 'http://localhost:5003')

def login_required(f):
    @functools.wraps(f)
    def decorated(*args, **kwargs):
        token = session.get('token')
        if not token:
            return redirect(url_for('login'))
        resp = requests.post(f'{AUTH}/validate', json={'token': token}, timeout=5)
        if not resp.ok or not resp.json().get('valid'):
            session.clear()
            return redirect(url_for('login'))
        session['user_id'] = resp.json()['user_id']
        session['username'] = resp.json()['username']
        return f(*args, **kwargs)
    return decorated

# ── Auth routes ──────────────────────────────────────────────────

@app.route('/')
def index():
    return redirect(url_for('library') if session.get('token') else url_for('login'))

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        resp = requests.post(f'{AUTH}/login', json={'username': request.form['username'], 'password': request.form['password']}, timeout=5)
        data = resp.json()
        if resp.ok:
            session['token'] = data['token']
            session['username'] = data['username']
            session['user_id'] = data['user_id']
            return redirect(url_for('library'))
        flash(data.get('error', 'Login failed'))
    return render_template('login.html')

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))

# ── Stream routes ────────────────────────────────────────────────

@app.route('/library')
@login_required
def library():
    resp = requests.get(f'{DB}/videos', timeout=5)
    videos = resp.json().get('videos', []) if resp.ok else []
    return render_template('library.html', username=session.get('username'), videos=videos, upload_url='http://localhost:5000')

@app.route('/watch/<int:video_id>')
@login_required
def watch(video_id):
    resp = requests.get(f'{DB}/videos/{video_id}', timeout=5)
    if not resp.ok:
        flash('Video not found')
        return redirect(url_for('library'))
    return render_template('watch.html', username=session.get('username'), video=resp.json())

@app.route('/stream/<filename>')
@login_required
def stream(filename):
    file_resp = requests.get(f'{FILES}/stream/{filename}', stream=True, timeout=30)
    if not file_resp.ok:
        return 'File not found', 404
    def generate():
        for chunk in file_resp.iter_content(chunk_size=8192):
            yield chunk
    return Response(generate(),
        content_type=file_resp.headers.get('Content-Type', 'video/mp4'),
        headers={'Accept-Ranges': 'bytes', 'Content-Length': file_resp.headers.get('Content-Length', '')})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5004)
