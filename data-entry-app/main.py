"""
Entry point for Google App Engine
"""
import os

# Set port for App Engine
port = int(os.environ.get('PORT', 8080))

from app import app

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=port, debug=False)
