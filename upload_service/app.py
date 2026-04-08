"""
Upload Service - Port 5000
Handles: register, login, upload video
Talks to: Auth Service, File Service, MySQL Service
"""
from flask import Flask, render_template, request, redirect, url_for, session, flash
import requests, os, functools

app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY', 'dev-secret')
app.config['MAX_CONTENT_LENGTH'] = 2 * 1024 * 1024 * 1024  # 2GB

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
    return redirect(url_for('upload') if session.get('token') else url_for('login'))

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        resp = requests.post(f'{AUTH}/login', json={'username': request.form['username'], 'password': request.form['password']}, timeout=5)
        data = resp.json()
        if resp.ok:
            session['token'] = data['token']
            session['username'] = data['username']
            session['user_id'] = data['user_id']
            return redirect(url_for('upload'))
        flash(data.get('error', 'Login failed'))
    return render_template('login.html')

@app.route('/register', methods=['GET', 'POST'])
def register():
    if request.method == 'POST':
        resp = requests.post(f'{AUTH}/register', json={'username': request.form['username'], 'email': request.form['email'], 'password': request.form['password']}, timeout=5)
        data = resp.json()
        if resp.ok:
            session['token'] = data['token']
            session['username'] = data['username']
            return redirect(url_for('upload'))
        flash(data.get('error', 'Registration failed'))
    return render_template('register.html')

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))

# ── Upload route ─────────────────────────────────────────────────

@app.route('/upload', methods=['GET', 'POST'])
@login_required
def upload():
    if request.method == 'POST':
        video = request.files.get('video')
        title = request.form.get('title', '').strip() or video.filename

        # 1. Send file to File Service
        file_resp = requests.post(f'{FILES}/upload',
            files={'file': (video.filename, video.stream, video.content_type)}, timeout=300)
        if not file_resp.ok:
            flash('File upload failed: ' + file_resp.json().get('error', ''))
            return redirect(request.url)
        fd = file_resp.json()

        # 2. Save metadata to MySQL Service
        db_resp = requests.post(f'{DB}/videos', json={
            'title': title, 'filename': fd['filename'],
            'file_path': f'/app/storage/{fd["filename"]}',
            'file_size': fd.get('size'), 'content_type': fd.get('content_type'),
            'uploaded_by': session['user_id']
        }, timeout=5)
        if not db_resp.ok:
            flash('Metadata save failed')
            return redirect(request.url)

        flash(f'"{title}" uploaded successfully!')
        return redirect(url_for('upload'))

    # GET — show upload form + list of user's videos
    videos_resp = requests.get(f'{DB}/videos', timeout=5)
    videos = videos_resp.json().get('videos', []) if videos_resp.ok else []
    return render_template('upload.html', username=session.get('username'), videos=videos, stream_url='http://localhost:5004')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
