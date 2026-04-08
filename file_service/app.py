from flask import Flask, request, jsonify, send_file, abort
import os, uuid
from pathlib import Path
from werkzeug.utils import secure_filename

app = Flask(__name__)
STORAGE_DIR = '/app/storage'
Path(STORAGE_DIR).mkdir(parents=True, exist_ok=True)
ALLOWED = {'mp4', 'avi', 'mov', 'mkv', 'webm', 'flv', 'wmv'}

@app.route('/health')
def health():
    return jsonify({'status': 'ok'})

@app.route('/upload', methods=['POST'])
def upload():
    if 'file' not in request.files:
        return jsonify({'error': 'No file'}), 400
    f = request.files['file']
    ext = f.filename.rsplit('.', 1)[-1].lower()
    if ext not in ALLOWED:
        return jsonify({'error': 'File type not allowed'}), 400
    filename = f'{uuid.uuid4().hex}.{ext}'
    path = os.path.join(STORAGE_DIR, filename)
    f.save(path)
    return jsonify({'filename': filename, 'original': f.filename, 'size': os.path.getsize(path), 'content_type': f.content_type}), 201

@app.route('/stream/<filename>')
def stream(filename):
    path = os.path.join(STORAGE_DIR, secure_filename(filename))
    if not os.path.exists(path):
        abort(404)
    ext = filename.rsplit('.', 1)[-1].lower()
    mime = {'mp4': 'video/mp4', 'webm': 'video/webm', 'avi': 'video/x-msvideo', 'mov': 'video/quicktime'}.get(ext, 'video/mp4')
    return send_file(path, mimetype=mime, conditional=True)

@app.route('/delete/<filename>', methods=['DELETE'])
def delete(filename):
    path = os.path.join(STORAGE_DIR, secure_filename(filename))
    if os.path.exists(path):
        os.remove(path)
    return jsonify({'message': 'Deleted'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5002)
