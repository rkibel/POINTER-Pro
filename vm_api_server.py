#!/usr/bin/env python3
"""
Flask API Server for POINTER Preprocessing
Deploy this on your GCloud VM to handle preprocessing requests from the iOS app
"""

from flask import Flask, request, jsonify, send_file
import os
import subprocess
import json
from datetime import datetime
from pathlib import Path
import base64
import signal
import psutil

app = Flask(__name__)

# Configuration
DATA_DIR = os.path.expanduser("~/data")
PREPROC_SCRIPT = os.path.expanduser("~/BoxDreamer/src/demo/preproc.py")
INFERENCE_SCRIPT = os.path.expanduser("~/BoxDreamer/src/demo/inference.py")

# Track running inference processes
# Format: {dataset_id: {"pid": int, "process": subprocess.Popen, "started": datetime}}
running_inference = {}

# Ensure data directory exists
os.makedirs(DATA_DIR, exist_ok=True)


@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'data_dir': DATA_DIR
    })


@app.route('/datasets', methods=['GET'])
def list_datasets():
    """List all available preprocessed datasets"""
    try:
        datasets = []

        if os.path.exists(DATA_DIR):
            for item in os.listdir(DATA_DIR):
                item_path = os.path.join(DATA_DIR, item)
                if os.path.isdir(item_path) and item.startswith('dataset_'):
                    # Try to read metadata
                    metadata_path = os.path.join(item_path, 'metadata.json')
                    if os.path.exists(metadata_path):
                        with open(metadata_path, 'r') as f:
                            metadata = json.load(f)
                            datasets.append(metadata)
                    else:
                        # Create basic metadata from folder
                        reference_dir = os.path.join(item_path, 'reference')
                        image_count = 0
                        if os.path.exists(reference_dir):
                            image_count = len([f for f in os.listdir(reference_dir)
                                               if f.endswith('.jpg')])

                        datasets.append({
                            'id': item,
                            'description': 'Unknown',
                            'timestamp': datetime.fromtimestamp(
                                os.path.getctime(item_path)
                            ).isoformat(),
                            'imageCount': image_count
                        })

        return jsonify({
            'datasets': datasets,
            'count': len(datasets)
        })

    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/preprocess', methods=['POST'])
def preprocess_images():
    """
    Receive images and trigger preprocessing

    Expected JSON body:
    {
        "description": "object description",
        "images": [
            {"data": "base64_encoded_jpeg", "index": 0},
            {"data": "base64_encoded_jpeg", "index": 1},
            ...
        ]
    }
    """
    try:
        data = request.get_json()

        if not data or 'description' not in data or 'images' not in data:
            return jsonify({'error': 'Missing required fields'}), 400

        description = data['description']
        images = data['images']

        if not images:
            return jsonify({'error': 'No images provided'}), 400

        # Generate dataset ID
        dataset_id = f"dataset_{int(datetime.now().timestamp())}"
        dataset_path = os.path.join(DATA_DIR, dataset_id)
        reference_path = os.path.join(dataset_path, 'reference')

        # Create directories
        os.makedirs(reference_path, exist_ok=True)

        # Save images
        for img_data in images:
            index = img_data.get('index', 0)
            img_base64 = img_data.get('data', '')

            # Decode base64 image
            img_bytes = base64.b64decode(img_base64)

            # Save with proper naming: 000000-color.jpg, 000001-color.jpg, etc.
            filename = f"{index:06d}-color.jpg"
            filepath = os.path.join(reference_path, filename)

            with open(filepath, 'wb') as f:
                f.write(img_bytes)

        # Save metadata
        metadata = {
            'id': dataset_id,
            'description': description,
            'timestamp': datetime.now().isoformat(),
            'imageCount': len(images)
        }

        metadata_path = os.path.join(dataset_path, 'metadata.json')
        with open(metadata_path, 'w') as f:
            json.dump(metadata, f, indent=2)

        # Run preprocessing script with conda environment activated
        # Need to use bash to activate conda environment
        cmd = f'''
        source /opt/conda/etc/profile.d/conda.sh && \
        conda activate boxdreamer && \
        python {PREPROC_SCRIPT} \
            --mode both \
            --ref_images_dir {reference_path} \
            --output_dir {dataset_path} \
            --use_grounding_dino \
            --text_prompt "{description}"
        '''

        # Run in background (non-blocking)
        # For production, consider using Celery or similar task queue
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            shell=True,
            executable='/usr/bin/bash',
            cwd=os.path.expanduser('~/BoxDreamer')
        )

        # Wait for completion (or set a timeout)
        stdout, stderr = process.communicate(timeout=300)  # 5 minute timeout

        if process.returncode != 0:
            error_msg = stderr.decode('utf-8') if stderr else 'Unknown error'
            return jsonify({
                'error': f'Preprocessing failed: {error_msg}',
                'dataset_id': dataset_id,
                'status': 'failed'
            }), 500

        return jsonify({
            'dataset_id': dataset_id,
            'description': description,
            'image_count': len(images),
            'status': 'completed',
            'message': 'Preprocessing completed successfully'
        })

    except subprocess.TimeoutExpired:
        return jsonify({
            'error': 'Preprocessing timeout (>5 minutes)',
            'dataset_id': dataset_id,
            'status': 'timeout'
        }), 504

    except Exception as e:
        return jsonify({
            'error': str(e),
            'status': 'error'
        }), 500


@app.route('/dataset/<dataset_id>', methods=['GET'])
def get_dataset(dataset_id):
    """Get metadata for a specific dataset"""
    try:
        dataset_path = os.path.join(DATA_DIR, dataset_id)
        metadata_path = os.path.join(dataset_path, 'metadata.json')

        if not os.path.exists(metadata_path):
            return jsonify({'error': 'Dataset not found'}), 404

        with open(metadata_path, 'r') as f:
            metadata = json.load(f)

        return jsonify(metadata)

    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/dataset/<dataset_id>/text_prompt', methods=['GET'])
def get_text_prompt(dataset_id):
    """Get the text prompt for a dataset"""
    try:
        dataset_path = os.path.join(DATA_DIR, dataset_id)
        # Text prompt is stored in reference_data directory
        text_prompt_path = os.path.join(
            dataset_path, 'reference_data', 'text_prompt.txt')

        if not os.path.exists(text_prompt_path):
            return jsonify({'error': 'Text prompt file not found'}), 404

        with open(text_prompt_path, 'r') as f:
            text_prompt = f.read().strip()

        return jsonify({
            'dataset_id': dataset_id,
            'text_prompt': text_prompt
        })

    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/dataset/<dataset_id>/text_prompt', methods=['PUT'])
def update_text_prompt(dataset_id):
    """Update the text prompt for a dataset

    Expected JSON body:
    {
        "text_prompt": "new description"
    }
    """
    try:
        data = request.get_json()

        if not data or 'text_prompt' not in data:
            return jsonify({'error': 'Missing text_prompt field'}), 400

        dataset_path = os.path.join(DATA_DIR, dataset_id)

        if not os.path.exists(dataset_path):
            return jsonify({'error': 'Dataset not found'}), 404

        text_prompt = data['text_prompt']
        # Text prompt is stored in reference_data directory
        text_prompt_path = os.path.join(
            dataset_path, 'reference_data', 'text_prompt.txt')

        # Write updated text prompt
        with open(text_prompt_path, 'w') as f:
            f.write(text_prompt)

        # Also update metadata if it exists
        metadata_path = os.path.join(dataset_path, 'metadata.json')
        if os.path.exists(metadata_path):
            with open(metadata_path, 'r') as f:
                metadata = json.load(f)
            metadata['description'] = text_prompt
            with open(metadata_path, 'w') as f:
                json.dump(metadata, f, indent=2)

        return jsonify({
            'dataset_id': dataset_id,
            'text_prompt': text_prompt,
            'message': 'Text prompt updated successfully'
        })

    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/dataset/<dataset_id>', methods=['DELETE'])
def delete_dataset(dataset_id):
    """Delete a dataset"""
    try:
        dataset_path = os.path.join(DATA_DIR, dataset_id)

        if not os.path.exists(dataset_path):
            return jsonify({'error': 'Dataset not found'}), 404

        # Delete directory and all contents
        import shutil
        shutil.rmtree(dataset_path)

        return jsonify({
            'message': f'Dataset {dataset_id} deleted successfully',
            'dataset_id': dataset_id
        })

    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/dataset/<dataset_id>/images', methods=['GET'])
def list_dataset_images(dataset_id):
    """List available images for a dataset (both reference and verification)

    Returns:
    {
        "dataset_id": "dataset_123",
        "reference_images": ["000000-color.jpg", "000001-color.jpg", ...],
        "verification_images": ["ref_00_bbox.jpg", "ref_01_bbox.jpg", ...]
    }
    """
    try:
        dataset_path = os.path.join(DATA_DIR, dataset_id)

        if not os.path.exists(dataset_path):
            return jsonify({'error': 'Dataset not found'}), 404

        # List reference images
        reference_path = os.path.join(dataset_path, 'reference')
        reference_images = []
        if os.path.exists(reference_path):
            reference_images = sorted([
                f for f in os.listdir(reference_path)
                if f.endswith(('.jpg', '.jpeg', '.png')) and '-color' in f
            ])

        # List verification images
        verification_path = os.path.join(dataset_path, 'verification')
        verification_images = []
        if os.path.exists(verification_path):
            verification_images = sorted([
                f for f in os.listdir(verification_path)
                if f.endswith(('.jpg', '.jpeg', '.png'))
            ])

        return jsonify({
            'dataset_id': dataset_id,
            'reference_images': reference_images,
            'verification_images': verification_images
        })

    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/dataset/<dataset_id>/image/<image_type>/<filename>', methods=['GET'])
def get_dataset_image(dataset_id, image_type, filename):
    """Serve an image from a dataset

    Args:
        dataset_id: The dataset ID
        image_type: Either 'reference' or 'verification'
        filename: The image filename

    Example:
        /dataset/dataset_123/image/reference/000000-color.jpg
        /dataset/dataset_123/image/verification/ref_00_bbox.jpg
    """
    try:
        dataset_path = os.path.join(DATA_DIR, dataset_id)

        if image_type not in ['reference', 'verification']:
            return jsonify({'error': 'Invalid image type. Must be "reference" or "verification"'}), 400

        image_dir = os.path.join(dataset_path, image_type)
        image_path = os.path.join(image_dir, filename)

        # Security check: ensure the path is within the expected directory
        if not os.path.abspath(image_path).startswith(os.path.abspath(image_dir)):
            return jsonify({'error': 'Invalid filename'}), 400

        if not os.path.exists(image_path):
            return jsonify({'error': 'Image not found'}), 404

        # Determine mimetype based on extension
        if filename.lower().endswith('.png'):
            mimetype = 'image/png'
        else:
            mimetype = 'image/jpeg'

        return send_file(image_path, mimetype=mimetype)

    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/inference/<dataset_id>/start', methods=['POST'])
def start_inference(dataset_id):
    """Start real-time inference on a preprocessed dataset

    Starts inference.py as a background process that connects to LiveKit
    and processes video frames continuously.

    Args:
        dataset_id: The dataset ID to run inference on

    Optional JSON body:
    {
        "livekit_url": "ws://localhost:7880",  (default)
        "api_key": "devkey",                    (default)
        "api_secret": "secret",                 (default)
        "room_name": "live"                     (default)
    }

    Returns:
        JSON response with inference status and process ID
    """
    try:
        # Check if inference is already running for this dataset
        if dataset_id in running_inference:
            pid = running_inference[dataset_id]['pid']
            # Check if process is still alive
            if psutil.pid_exists(pid):
                return jsonify({
                    'error': 'Inference already running for this dataset',
                    'dataset_id': dataset_id,
                    'pid': pid,
                    'status': 'already_running'
                }), 409

            # Process died, remove from tracking
            del running_inference[dataset_id]

        dataset_path = os.path.join(DATA_DIR, dataset_id)

        if not os.path.exists(dataset_path):
            return jsonify({'error': 'Dataset not found'}), 404

        # Look for the preprocessing bundle
        bundle_path = os.path.join(dataset_path, 'preprocessing_bundle.pkl')

        if not os.path.exists(bundle_path):
            return jsonify({
                'error': 'Preprocessing bundle not found. Dataset may not be fully preprocessed.',
                'expected_path': bundle_path
            }), 404

        # Get optional parameters from request
        data = request.get_json() if request.is_json else {}
        livekit_url = data.get('livekit_url', 'ws://localhost:7880')
        api_key = data.get('api_key', 'devkey')
        api_secret = data.get('api_secret', 'secret')
        room_name = data.get('room_name', 'live')

        # Run inference script as background daemon
        cmd = f'''
        source /opt/conda/etc/profile.d/conda.sh && \
        conda activate boxdreamer && \
        python {INFERENCE_SCRIPT} \
            --bundle_path {bundle_path} \
            --livekit_url {livekit_url} \
            --api_key {api_key} \
            --api_secret {api_secret} \
            --room_name {room_name}
        '''

        # Start as background process (daemon)
        log_path = os.path.join(dataset_path, 'inference.log')
        with open(log_path, 'w') as log_file:
            process = subprocess.Popen(
                cmd,
                stdout=log_file,
                stderr=subprocess.STDOUT,
                shell=True,
                executable='/usr/bin/bash',
                cwd=os.path.expanduser('~/BoxDreamer'),
                preexec_fn=os.setsid  # Create new process group
            )

        # Track the process
        running_inference[dataset_id] = {
            'pid': process.pid,
            'process': process,
            'started': datetime.now().isoformat(),
            'bundle_path': bundle_path,
            'log_path': log_path
        }

        return jsonify({
            'dataset_id': dataset_id,
            'pid': process.pid,
            'bundle_path': bundle_path,
            'log_path': log_path,
            'status': 'started',
            'message': 'Inference started successfully'
        })

    except Exception as e:
        return jsonify({
            'error': str(e),
            'status': 'error'
        }), 500


@app.route('/inference/<dataset_id>/status', methods=['GET'])
def get_inference_status(dataset_id):
    """Get the status of inference for a dataset

    Returns:
        JSON response with inference status
    """
    try:
        if dataset_id not in running_inference:
            return jsonify({
                'dataset_id': dataset_id,
                'status': 'not_running'
            })

        info = running_inference[dataset_id]
        pid = info['pid']

        # Check if process is still alive
        if not psutil.pid_exists(pid):
            del running_inference[dataset_id]
            return jsonify({
                'dataset_id': dataset_id,
                'status': 'stopped',
                'message': 'Process no longer running'
            })

        # Get process info
        try:
            proc = psutil.Process(pid)
            cpu_percent = proc.cpu_percent(interval=0.1)
            memory_mb = proc.memory_info().rss / 1024 / 1024
        except:
            cpu_percent = 0
            memory_mb = 0

        return jsonify({
            'dataset_id': dataset_id,
            'status': 'running',
            'pid': pid,
            'started': info['started'],
            'bundle_path': info['bundle_path'],
            'log_path': info.get('log_path'),
            'cpu_percent': cpu_percent,
            'memory_mb': memory_mb
        })

    except Exception as e:
        return jsonify({
            'error': str(e),
            'status': 'error'
        }), 500


@app.route('/inference/<dataset_id>/stop', methods=['POST'])
def stop_inference(dataset_id):
    """Stop inference for a dataset

    Returns:
        JSON response with stop status
    """
    try:
        if dataset_id not in running_inference:
            return jsonify({
                'error': 'No inference running for this dataset',
                'dataset_id': dataset_id,
                'status': 'not_running'
            }), 404

        info = running_inference[dataset_id]
        pid = info['pid']

        # Check if process exists
        if not psutil.pid_exists(pid):
            del running_inference[dataset_id]
            return jsonify({
                'dataset_id': dataset_id,
                'status': 'already_stopped',
                'message': 'Process was not running'
            })

        # Try graceful shutdown first (SIGINT)
        try:
            os.killpg(os.getpgid(pid), signal.SIGINT)
            # Wait a bit for graceful shutdown
            import time
            time.sleep(2)

            # Check if still alive
            if psutil.pid_exists(pid):
                # Force kill if still running
                os.killpg(os.getpgid(pid), signal.SIGKILL)
        except:
            pass

        del running_inference[dataset_id]

        return jsonify({
            'dataset_id': dataset_id,
            'status': 'stopped',
            'message': 'Inference stopped successfully'
        })

    except Exception as e:
        return jsonify({
            'error': str(e),
            'status': 'error'
        }), 500


@app.route('/inference/list', methods=['GET'])
def list_running_inference():
    """List all currently running inference processes

    Returns:
        JSON response with list of running inference
    """
    try:
        active = []
        dead_keys = []

        for dataset_id, info in running_inference.items():
            pid = info['pid']
            if psutil.pid_exists(pid):
                active.append({
                    'dataset_id': dataset_id,
                    'pid': pid,
                    'started': info['started'],
                    'bundle_path': info['bundle_path']
                })
            else:
                dead_keys.append(dataset_id)

        # Clean up dead processes
        for key in dead_keys:
            del running_inference[key]

        return jsonify({
            'count': len(active),
            'running_inference': active
        })

    except Exception as e:
        return jsonify({
            'error': str(e),
            'status': 'error'
        }), 500


if __name__ == '__main__':
    # Run on all interfaces, port 5000
    # For production, use a proper WSGI server like gunicorn
    app.run(host='0.0.0.0', port=5000, debug=False)
