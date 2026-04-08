from flask import Flask, request, jsonify
import mysql.connector, os

app = Flask(__name__)

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

@app.route('/videos', methods=['GET'])
def list_videos():
    conn = get_db(); cur = conn.cursor(dictionary=True)
    cur.execute('SELECT v.*, u.username FROM videos v JOIN users u ON v.uploaded_by=u.id ORDER BY v.uploaded_at DESC')
    videos = cur.fetchall()
    for v in videos:
        if v.get('uploaded_at'): v['uploaded_at'] = v['uploaded_at'].isoformat()
    cur.close(); conn.close()
    return jsonify({'videos': videos})

@app.route('/videos/<int:vid>', methods=['GET'])
def get_video(vid):
    conn = get_db(); cur = conn.cursor(dictionary=True)
    cur.execute('SELECT v.*, u.username FROM videos v JOIN users u ON v.uploaded_by=u.id WHERE v.id=%s', (vid,))
    video = cur.fetchone()
    cur.close(); conn.close()
    if not video: return jsonify({'error': 'Not found'}), 404
    if video.get('uploaded_at'): video['uploaded_at'] = video['uploaded_at'].isoformat()
    return jsonify(video)

@app.route('/videos', methods=['POST'])
def create_video():
    d = request.get_json()
    conn = get_db(); cur = conn.cursor()
    cur.execute('INSERT INTO videos (title, filename, file_path, file_size, content_type, uploaded_by) VALUES (%s,%s,%s,%s,%s,%s)',
        (d['title'], d['filename'], d['file_path'], d.get('file_size'), d.get('content_type'), d['uploaded_by']))
    conn.commit(); vid = cur.lastrowid
    cur.close(); conn.close()
    return jsonify({'video_id': vid}), 201

@app.route('/videos/<int:vid>', methods=['DELETE'])
def delete_video(vid):
    conn = get_db(); cur = conn.cursor()
    cur.execute('DELETE FROM videos WHERE id=%s', (vid,))
    conn.commit(); cur.close(); conn.close()
    return jsonify({'message': 'Deleted'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5003)
