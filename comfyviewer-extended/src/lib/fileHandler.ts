import { openDB, IDBPDatabase } from 'idb';

export interface MediaFile {
  id: string;
  name: string;
  path: string;
  type: 'image' | 'video';
  mimeType: string;
  size: number;
  width?: number;
  height?: number;
  duration?: number;
  fps?: number;
  codec?: string;
  thumbnail?: string;
  metadata?: ComfyUIMetadata;
  dateCreated: Date;
  dateModified: Date;
}

export interface ComfyUIMetadata {
  prompt?: string;
  negative_prompt?: string;
  seed?: number;
  steps?: number;
  cfg_scale?: number;
  sampler?: string;
  model?: string;
  loras?: Array<{name: string; weight: number}>;
  workflow?: any;
  extra?: Record<string, any>;
}

const IMAGE_EXTENSIONS = ['.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp'];
const VIDEO_EXTENSIONS = ['.mp4', '.webm', '.avi', '.mov', '.mkv', '.m4v'];

export class FileHandler {
  private db: IDBPDatabase | null = null;
  private readonly DB_NAME = 'ComfyViewerExtended';
  private readonly DB_VERSION = 1;

  async init() {
    this.db = await openDB(this.DB_NAME, this.DB_VERSION, {
      upgrade(db) {
        // Create media store
        if (!db.objectStoreNames.contains('media')) {
          const mediaStore = db.createObjectStore('media', { keyPath: 'id' });
          mediaStore.createIndex('type', 'type');
          mediaStore.createIndex('dateCreated', 'dateCreated');
          mediaStore.createIndex('model', 'metadata.model');
        }

        // Create thumbnails store
        if (!db.objectStoreNames.contains('thumbnails')) {
          db.createObjectStore('thumbnails', { keyPath: 'id' });
        }
      },
    });
  }

  isMediaFile(filename: string): boolean {
    const ext = filename.toLowerCase().substring(filename.lastIndexOf('.'));
    return [...IMAGE_EXTENSIONS, ...VIDEO_EXTENSIONS].includes(ext);
  }

  getFileType(filename: string): 'image' | 'video' | null {
    const ext = filename.toLowerCase().substring(filename.lastIndexOf('.'));
    if (IMAGE_EXTENSIONS.includes(ext)) return 'image';
    if (VIDEO_EXTENSIONS.includes(ext)) return 'video';
    return null;
  }

  async processFile(file: File): Promise<MediaFile> {
    const type = this.getFileType(file.name);
    if (!type) throw new Error('Unsupported file type');

    const mediaFile: MediaFile = {
      id: this.generateId(),
      name: file.name,
      path: URL.createObjectURL(file),
      type,
      mimeType: file.type,
      size: file.size,
      dateCreated: new Date(file.lastModified),
      dateModified: new Date(file.lastModified),
    };

    // Process based on type
    if (type === 'image') {
      await this.processImage(file, mediaFile);
    } else if (type === 'video') {
      await this.processVideo(file, mediaFile);
    }

    // Extract ComfyUI metadata if present
    if (type === 'image' && file.type === 'image/png') {
      mediaFile.metadata = await this.extractPNGMetadata(file);
    }

    // Store in IndexedDB
    await this.saveMedia(mediaFile);

    return mediaFile;
  }

  private async processImage(file: File, mediaFile: MediaFile) {
    return new Promise<void>((resolve) => {
      const img = new Image();
      img.onload = async () => {
        mediaFile.width = img.width;
        mediaFile.height = img.height;

        // Generate thumbnail
        const thumbnail = await this.generateImageThumbnail(img);
        mediaFile.thumbnail = thumbnail;

        resolve();
      };
      img.src = mediaFile.path;
    });
  }

  private async processVideo(file: File, mediaFile: MediaFile) {
    return new Promise<void>((resolve) => {
      const video = document.createElement('video');
      video.preload = 'metadata';

      video.onloadedmetadata = async () => {
        mediaFile.width = video.videoWidth;
        mediaFile.height = video.videoHeight;
        mediaFile.duration = video.duration;

        // Try to extract FPS (approximate)
        if (video.duration > 0) {
          // This is a rough estimate, actual FPS extraction would require parsing video metadata
          mediaFile.fps = 30; // Default assumption
        }

        // Generate thumbnail from first frame
        const thumbnail = await this.generateVideoThumbnail(video);
        mediaFile.thumbnail = thumbnail;

        resolve();
      };

      video.onerror = () => {
        console.error('Failed to load video metadata');
        resolve();
      };

      video.src = mediaFile.path;
    });
  }

  private async generateImageThumbnail(img: HTMLImageElement): Promise<string> {
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d');
    if (!ctx) return '';

    const maxSize = 200;
    const scale = Math.min(maxSize / img.width, maxSize / img.height);

    canvas.width = img.width * scale;
    canvas.height = img.height * scale;

    ctx.drawImage(img, 0, 0, canvas.width, canvas.height);

    return canvas.toDataURL('image/jpeg', 0.8);
  }

  private async generateVideoThumbnail(video: HTMLVideoElement): Promise<string> {
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d');
    if (!ctx) return '';

    // Seek to 10% of video duration for thumbnail
    video.currentTime = video.duration * 0.1;

    return new Promise((resolve) => {
      video.onseeked = () => {
        const maxSize = 200;
        const scale = Math.min(maxSize / video.videoWidth, maxSize / video.videoHeight);

        canvas.width = video.videoWidth * scale;
        canvas.height = video.videoHeight * scale;

        ctx.drawImage(video, 0, 0, canvas.width, canvas.height);

        resolve(canvas.toDataURL('image/jpeg', 0.8));
      };
    });
  }

  private async extractPNGMetadata(file: File): Promise<ComfyUIMetadata | undefined> {
    try {
      const arrayBuffer = await file.arrayBuffer();
      const uint8Array = new Uint8Array(arrayBuffer);

      // Look for ComfyUI metadata in PNG chunks
      // PNG format: 8-byte signature, then chunks
      let offset = 8; // Skip PNG signature

      while (offset < uint8Array.length) {
        // Read chunk length (4 bytes, big-endian)
        const length = (uint8Array[offset] << 24) |
                      (uint8Array[offset + 1] << 16) |
                      (uint8Array[offset + 2] << 8) |
                      uint8Array[offset + 3];

        // Read chunk type (4 bytes)
        const typeBytes = uint8Array.slice(offset + 4, offset + 8);
        const type = String.fromCharCode(...typeBytes);

        // Look for tEXt or iTXt chunks that might contain ComfyUI data
        if (type === 'tEXt' || type === 'iTXt') {
          const data = uint8Array.slice(offset + 8, offset + 8 + length);
          const text = new TextDecoder().decode(data);

          // ComfyUI typically stores data with keys like "prompt", "workflow", etc.
          if (text.includes('prompt') || text.includes('workflow')) {
            try {
              // Parse the JSON data
              const jsonStart = text.indexOf('{');
              if (jsonStart !== -1) {
                const jsonText = text.substring(jsonStart);
                const metadata = JSON.parse(jsonText);

                return this.parseComfyUIMetadata(metadata);
              }
            } catch (e) {
              console.error('Failed to parse metadata JSON:', e);
            }
          }
        }

        // Move to next chunk
        offset += 8 + length + 4; // 4 bytes length + 4 bytes type + data + 4 bytes CRC
      }
    } catch (error) {
      console.error('Failed to extract PNG metadata:', error);
    }

    return undefined;
  }

  private parseComfyUIMetadata(data: any): ComfyUIMetadata {
    const metadata: ComfyUIMetadata = {};

    // Extract common ComfyUI parameters
    if (data.prompt) metadata.prompt = data.prompt;
    if (data.negative_prompt) metadata.negative_prompt = data.negative_prompt;
    if (data.seed) metadata.seed = data.seed;
    if (data.steps) metadata.steps = data.steps;
    if (data.cfg_scale) metadata.cfg_scale = data.cfg_scale;
    if (data.sampler) metadata.sampler = data.sampler;
    if (data.model) metadata.model = data.model;
    if (data.loras) metadata.loras = data.loras;
    if (data.workflow) metadata.workflow = data.workflow;

    // Store any extra data
    const knownKeys = ['prompt', 'negative_prompt', 'seed', 'steps', 'cfg_scale', 'sampler', 'model', 'loras', 'workflow'];
    const extraKeys = Object.keys(data).filter(key => !knownKeys.includes(key));
    if (extraKeys.length > 0) {
      metadata.extra = {};
      extraKeys.forEach(key => {
        metadata.extra![key] = data[key];
      });
    }

    return metadata;
  }

  async saveMedia(media: MediaFile) {
    if (!this.db) await this.init();
    await this.db!.put('media', media);

    // Save thumbnail separately to keep main store lighter
    if (media.thumbnail) {
      await this.db!.put('thumbnails', {
        id: media.id,
        data: media.thumbnail
      });
    }
  }

  async getAllMedia(): Promise<MediaFile[]> {
    if (!this.db) await this.init();
    return await this.db!.getAll('media');
  }

  async getMediaByType(type: 'image' | 'video'): Promise<MediaFile[]> {
    if (!this.db) await this.init();
    return await this.db!.getAllFromIndex('media', 'type', type);
  }

  async deleteMedia(id: string) {
    if (!this.db) await this.init();
    await this.db!.delete('media', id);
    await this.db!.delete('thumbnails', id);
  }

  async clearAll() {
    if (!this.db) await this.init();
    await this.db!.clear('media');
    await this.db!.clear('thumbnails');
  }

  private generateId(): string {
    return `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  }
}