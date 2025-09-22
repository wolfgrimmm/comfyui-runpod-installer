#!/usr/bin/env python3
"""
Standalone Model Downloader for ComfyUI
A Gradio-based application for downloading and managing AI models
"""

import gradio as gr
import os
import sys
import json
import threading
import time
import argparse
from pathlib import Path
from typing import Dict, List, Optional

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Import the model downloader backend
try:
    from model_downloader import ModelDownloader
    MODEL_DOWNLOADER_AVAILABLE = True
except ImportError:
    MODEL_DOWNLOADER_AVAILABLE = False
    print("⚠️ Model downloader not available - install huggingface_hub")

# Default paths
DEFAULT_MODELS_PATH = "/workspace/models"
if not os.path.exists(DEFAULT_MODELS_PATH):
    # Fallback for local development
    DEFAULT_MODELS_PATH = os.path.expanduser("~/ComfyUI/models")

# Global variables
downloader = None
download_status = {}
current_downloads = {}

def initialize_downloader(models_path):
    """Initialize the model downloader with the given path"""
    global downloader
    if MODEL_DOWNLOADER_AVAILABLE:
        downloader = ModelDownloader(models_path)
        return f"✅ Initialized with models path: {models_path}"
    else:
        return "❌ Model downloader not available. Please install huggingface_hub"

def get_disk_usage():
    """Get disk usage information"""
    if not downloader:
        return "Downloader not initialized"

    try:
        usage = downloader.get_disk_usage()
        return f"💾 Disk Usage: {usage['used']:.1f}GB / {usage['total']:.1f}GB ({usage['percent']:.1f}% used) - {usage['free']:.1f}GB free"
    except:
        return "Unable to get disk usage"

def refresh_bundles():
    """Get available bundles organized by category"""
    if not downloader:
        return gr.update(choices=[], value=None)

    bundles = downloader.get_bundles()

    # Organize bundles by category
    bundle_choices = []
    for bundle_id, bundle_data in bundles.items():
        category = bundle_data.get('category', 'Other')
        name = bundle_data.get('name', bundle_id)
        choice_label = f"[{category}] {name}"
        bundle_choices.append((choice_label, bundle_id))

    return gr.update(choices=bundle_choices)

def get_bundle_info(bundle_id_with_label):
    """Get detailed information about a bundle"""
    if not bundle_id_with_label or not downloader:
        return ""

    # Extract bundle_id from the label
    bundle_id = bundle_id_with_label
    if isinstance(bundle_id_with_label, str) and '] ' in bundle_id_with_label:
        bundle_id = bundle_id_with_label.split('] ', 1)[1]
        # Find the actual bundle_id by matching the name
        bundles = downloader.get_bundles()
        for bid, bdata in bundles.items():
            if bdata.get('name') == bundle_id:
                bundle_id = bid
                break

    bundles = downloader.get_bundles()
    if bundle_id not in bundles:
        return "Bundle not found"

    bundle = bundles[bundle_id]

    info = f"**{bundle.get('name', bundle_id)}**\n\n"
    info += f"📝 {bundle.get('description', 'No description available')}\n\n"
    info += f"**Models included:**\n"

    total_size = 0
    for model in bundle.get('models', []):
        model_name = model.get('filename', model.get('repo_id', 'Unknown'))
        model_size = model.get('size', 'Unknown size')
        info += f"• {model_name} ({model_size})\n"

    info += f"\n**Category:** {bundle.get('category', 'Other')}\n"

    return info

def download_bundle(bundle_id_with_label, progress=gr.Progress()):
    """Download all models in a bundle"""
    if not bundle_id_with_label or not downloader:
        return "❌ Please select a bundle first"

    # Extract bundle_id
    bundle_id = bundle_id_with_label
    if isinstance(bundle_id_with_label, str) and '] ' in bundle_id_with_label:
        bundle_name = bundle_id_with_label.split('] ', 1)[1]
        bundles = downloader.get_bundles()
        for bid, bdata in bundles.items():
            if bdata.get('name') == bundle_name:
                bundle_id = bid
                break

    try:
        progress(0, desc="Starting bundle download...")
        result = downloader.download_bundle(
            bundle_id,
            progress_callback=lambda p, d: progress(p/100, desc=d)
        )

        if result.get('bundle_download_id'):
            return f"✅ Bundle download started! Check the Downloads tab for progress."
        else:
            return f"❌ Failed to start bundle download"
    except Exception as e:
        return f"❌ Error: {str(e)}"

def search_huggingface(query, progress=gr.Progress()):
    """Search for models on HuggingFace"""
    if not query or not downloader:
        return []

    try:
        progress(0, desc="Searching HuggingFace...")
        results = downloader.search_models(query)
        progress(1, desc="Search complete")

        # Format results for display
        formatted_results = []
        for model in results:
            formatted_results.append([
                model.get('name', 'Unknown'),
                model.get('downloads', 0),
                model.get('likes', 0),
                ', '.join(model.get('tags', [])[:3])
            ])

        return formatted_results
    except Exception as e:
        return [[f"Error: {str(e)}", "", "", ""]]

def download_hf_model(model_name, filename=None, progress=gr.Progress()):
    """Download a model from HuggingFace"""
    if not model_name or not downloader:
        return "❌ Please provide a model name"

    try:
        progress(0, desc=f"Starting download of {model_name}...")

        download_id = downloader.download_model(
            model_name,
            filename=filename,
            progress_callback=lambda p, d: progress(p/100, desc=d)
        )

        if download_id:
            return f"✅ Download started for {model_name}"
        else:
            return f"❌ Failed to start download"
    except Exception as e:
        return f"❌ Error: {str(e)}"

def get_installed_models():
    """Get list of installed models"""
    if not downloader:
        return "Downloader not initialized"

    try:
        models = downloader.get_installed_models()

        if not models:
            return "No models installed yet"

        output = ""
        for category, model_list in models.items():
            output += f"\n**{category.replace('_', ' ').title()}**\n"
            for model in model_list:
                output += f"• {model['name']} ({model['size']})\n"

        return output
    except Exception as e:
        return f"Error loading models: {str(e)}"

def delete_model(model_path):
    """Delete a model file"""
    if not model_path or not downloader:
        return "❌ Please provide a model path"

    try:
        success = downloader.delete_model(model_path)
        if success:
            return f"✅ Model deleted: {model_path}"
        else:
            return f"❌ Failed to delete model"
    except Exception as e:
        return f"❌ Error: {str(e)}"

def get_download_status():
    """Get current download status"""
    if not downloader:
        return "Downloader not initialized"

    try:
        downloads = downloader.get_downloads()

        if not downloads:
            return "No active downloads"

        output = "**Active Downloads:**\n\n"
        for download_id, status in downloads.items():
            repo_id = status.get('repo_id', 'Unknown')
            progress = status.get('progress', 0)
            state = status.get('status', 'unknown')

            output += f"📥 {repo_id}\n"
            output += f"   Status: {state} - {progress:.1f}%\n\n"

        return output
    except:
        return "No active downloads"

def create_interface():
    """Create the Gradio interface"""

    with gr.Blocks(title="ComfyUI Model Downloader", theme=gr.themes.Soft()) as app:
        gr.Markdown("# 🚀 ComfyUI Model Downloader")

        with gr.Row():
            with gr.Column(scale=2):
                disk_usage_text = gr.Markdown(get_disk_usage())
            with gr.Column(scale=1):
                refresh_btn = gr.Button("🔄 Refresh", size="sm")

        with gr.Tabs():
            # Bundles Tab
            with gr.Tab("📦 Bundles"):
                gr.Markdown("Download pre-configured model bundles with a single click")

                with gr.Row():
                    with gr.Column(scale=1):
                        bundle_dropdown = gr.Dropdown(
                            label="Select Bundle",
                            choices=[],
                            interactive=True
                        )
                        bundle_info = gr.Markdown("Select a bundle to see details")
                        download_bundle_btn = gr.Button("⬇️ Download Bundle", variant="primary")
                        bundle_status = gr.Markdown("")

                    with gr.Column(scale=2):
                        gr.Markdown("### Available Bundles")
                        gr.Markdown("""
                        **Bundle Categories:**
                        - 🎨 **Image Generation** - FLUX, SDXL, Stable Diffusion models
                        - 🎬 **Video Generation** - Video models and LoRAs
                        - 🔧 **Utility Models** - VAEs, upscalers, controlnets
                        - ⚡ **Text Encoders** - CLIP and other text encoders

                        Select a bundle from the dropdown to see what's included.
                        """)

            # Search HuggingFace Tab
            with gr.Tab("🤗 HuggingFace"):
                gr.Markdown("Search and download models from HuggingFace Hub")

                with gr.Row():
                    search_input = gr.Textbox(
                        label="Search Query",
                        placeholder="e.g., FLUX, SDXL, ControlNet...",
                        scale=3
                    )
                    search_btn = gr.Button("🔍 Search", scale=1)

                search_results = gr.Dataframe(
                    headers=["Model", "Downloads", "Likes", "Tags"],
                    interactive=False,
                    wrap=True
                )

                with gr.Row():
                    model_name_input = gr.Textbox(
                        label="Model Name/Repo ID",
                        placeholder="e.g., runwayml/stable-diffusion-v1-5"
                    )
                    filename_input = gr.Textbox(
                        label="Specific File (optional)",
                        placeholder="e.g., model.safetensors"
                    )
                    download_hf_btn = gr.Button("⬇️ Download", variant="primary")

                hf_status = gr.Markdown("")

            # Installed Models Tab
            with gr.Tab("💾 Installed"):
                gr.Markdown("View and manage installed models")

                installed_models_text = gr.Markdown("Click refresh to load installed models")

                with gr.Row():
                    refresh_installed_btn = gr.Button("🔄 Refresh Installed Models")

                delete_input = gr.Textbox(
                    label="Model Path to Delete",
                    placeholder="/workspace/models/checkpoints/model.safetensors"
                )
                delete_btn = gr.Button("🗑️ Delete Model", variant="stop")
                delete_status = gr.Markdown("")

            # Downloads Tab
            with gr.Tab("📊 Downloads"):
                gr.Markdown("Monitor active downloads")

                downloads_text = gr.Markdown("No active downloads")

                with gr.Row():
                    refresh_downloads_btn = gr.Button("🔄 Refresh Downloads")
                    clear_completed_btn = gr.Button("🧹 Clear Completed")

        # Event handlers
        def refresh_all():
            return (
                get_disk_usage(),
                refresh_bundles(),
                get_download_status(),
                get_installed_models()
            )

        # Refresh button
        refresh_btn.click(
            refresh_all,
            outputs=[disk_usage_text, bundle_dropdown, downloads_text, installed_models_text]
        )

        # Bundle events
        bundle_dropdown.change(
            get_bundle_info,
            inputs=[bundle_dropdown],
            outputs=[bundle_info]
        )

        download_bundle_btn.click(
            download_bundle,
            inputs=[bundle_dropdown],
            outputs=[bundle_status]
        )

        # HuggingFace events
        search_btn.click(
            search_huggingface,
            inputs=[search_input],
            outputs=[search_results]
        )

        download_hf_btn.click(
            download_hf_model,
            inputs=[model_name_input, filename_input],
            outputs=[hf_status]
        )

        # Installed models events
        refresh_installed_btn.click(
            get_installed_models,
            outputs=[installed_models_text]
        )

        delete_btn.click(
            delete_model,
            inputs=[delete_input],
            outputs=[delete_status]
        )

        # Downloads events
        refresh_downloads_btn.click(
            get_download_status,
            outputs=[downloads_text]
        )

        # Auto-refresh downloads every 5 seconds when tab is active
        app.load(
            refresh_all,
            outputs=[disk_usage_text, bundle_dropdown, downloads_text, installed_models_text]
        )

    return app

def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description="ComfyUI Model Downloader")
    parser.add_argument("--models-path", type=str, default=DEFAULT_MODELS_PATH,
                       help="Path to models directory")
    parser.add_argument("--share", action="store_true",
                       help="Create public Gradio link")
    parser.add_argument("--port", type=int, default=7860,
                       help="Port to run on (default: 7860)")
    parser.add_argument("--host", type=str, default="0.0.0.0",
                       help="Host to bind to (default: 0.0.0.0)")
    args = parser.parse_args()

    # Initialize the downloader
    print(initialize_downloader(args.models_path))

    # Create and launch the interface
    app = create_interface()

    print(f"\n🚀 Starting ComfyUI Model Downloader")
    print(f"📁 Models path: {args.models_path}")
    print(f"🌐 Access at: http://{args.host}:{args.port}")
    if args.share:
        print("📡 Creating public share link...")

    try:
        app.launch(
            server_name=args.host,
            server_port=args.port,
            share=args.share,
            inbrowser=False,
            quiet=False
        )
    except KeyboardInterrupt:
        print("\n👋 Shutting down...")
    except Exception as e:
        print(f"❌ Error: {e}")

if __name__ == "__main__":
    main()