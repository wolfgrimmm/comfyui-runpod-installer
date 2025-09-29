'use client';

import React, { useState, useEffect } from 'react';
import JSZip from 'jszip';
import { saveAs } from 'file-saver';
import {
  Download,
  FolderDown,
  Check,
  X,
  Loader2,
  ChevronDown,
  Package,
  FileJson
} from 'lucide-react';

interface MediaFile {
  id: string;
  name: string;
  path: string;
  type: 'image' | 'video';
  size: number;
  metadata?: any;
  selected?: boolean;
  thumbnail?: string;
  dateCreated?: Date;
  model?: string;
  prompt?: string;
}

interface BulkDownloaderProps {
  files: MediaFile[];
  onSelectionChange?: (selectedFiles: MediaFile[]) => void;
  onClose?: () => void;
}

export const BulkDownloader: React.FC<BulkDownloaderProps> = ({
  files,
  onSelectionChange,
  onClose
}) => {
  const [selectedFiles, setSelectedFiles] = useState<Set<string>>(new Set());
  const [isDownloading, setIsDownloading] = useState(false);
  const [downloadProgress, setDownloadProgress] = useState(0);
  const [includeMetadata, setIncludeMetadata] = useState(true);
  const [organizationMethod, setOrganizationMethod] = useState<'flat' | 'date' | 'model' | 'type'>('flat');
  const [showOptions, setShowOptions] = useState(false);

  const toggleFileSelection = (fileId: string) => {
    const newSelected = new Set(selectedFiles);
    if (newSelected.has(fileId)) {
      newSelected.delete(fileId);
    } else {
      newSelected.add(fileId);
    }
    setSelectedFiles(newSelected);

    if (onSelectionChange) {
      const selectedFilesList = files.filter(f => newSelected.has(f.id));
      onSelectionChange(selectedFilesList);
    }
  };

  const selectAll = () => {
    const allIds = new Set(files.map(f => f.id));
    setSelectedFiles(allIds);
    if (onSelectionChange) {
      onSelectionChange(files);
    }
  };

  const deselectAll = () => {
    setSelectedFiles(new Set());
    if (onSelectionChange) {
      onSelectionChange([]);
    }
  };

  const downloadSingleFile = async (file: MediaFile) => {
    try {
      const response = await fetch(file.path);
      const blob = await response.blob();
      saveAs(blob, file.name);

      // Download metadata if requested
      if (includeMetadata && file.metadata) {
        const metadataBlob = new Blob([JSON.stringify(file.metadata, null, 2)], {
          type: 'application/json'
        });
        const metadataName = file.name.replace(/\.[^/.]+$/, '.json');
        saveAs(metadataBlob, metadataName);
      }
    } catch (error) {
      console.error('Failed to download file:', error);
    }
  };

  const getOrganizedPath = (file: MediaFile): string => {
    switch (organizationMethod) {
      case 'date':
        const date = file.dateCreated || new Date();
        const dateStr = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
        return `${dateStr}/${file.name}`;

      case 'model':
        const model = file.model || 'unknown-model';
        return `${model}/${file.name}`;

      case 'type':
        return `${file.type}s/${file.name}`;

      default:
        return file.name;
    }
  };

  const downloadAsZip = async () => {
    setIsDownloading(true);
    setDownloadProgress(0);

    const zip = new JSZip();
    const selectedFilesList = files.filter(f => selectedFiles.has(f.id));
    let processed = 0;

    for (const file of selectedFilesList) {
      try {
        // Fetch the file
        const response = await fetch(file.path);
        const blob = await response.blob();

        // Add to zip with organized path
        const filePath = getOrganizedPath(file);
        zip.file(filePath, blob);

        // Add metadata if requested
        if (includeMetadata && file.metadata) {
          const metadataPath = filePath.replace(/\.[^/.]+$/, '.json');
          zip.file(metadataPath, JSON.stringify(file.metadata, null, 2));
        }

        // Update progress
        processed++;
        setDownloadProgress(Math.round((processed / selectedFilesList.length) * 100));
      } catch (error) {
        console.error(`Failed to add ${file.name} to zip:`, error);
      }
    }

    // Generate and download zip
    try {
      const zipBlob = await zip.generateAsync({
        type: 'blob',
        compression: 'DEFLATE',
        compressionOptions: { level: 6 }
      });

      const timestamp = new Date().toISOString().slice(0, 19).replace(/[:-]/g, '');
      const zipName = `comfyui-media-${timestamp}.zip`;
      saveAs(zipBlob, zipName);
    } catch (error) {
      console.error('Failed to generate zip:', error);
    } finally {
      setIsDownloading(false);
      setDownloadProgress(0);
    }
  };

  const getTotalSize = () => {
    const selectedFilesList = files.filter(f => selectedFiles.has(f.id));
    const totalBytes = selectedFilesList.reduce((sum, file) => sum + file.size, 0);
    return formatFileSize(totalBytes);
  };

  const formatFileSize = (bytes: number): string => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
  };

  return (
    <div className="fixed inset-0 bg-black/50 backdrop-blur-sm z-50 flex items-center justify-center p-4">
      <div className="bg-gray-900 rounded-xl shadow-2xl max-w-4xl w-full max-h-[80vh] overflow-hidden">
        {/* Header */}
        <div className="border-b border-gray-800 p-6">
          <div className="flex items-center justify-between">
            <div>
              <h2 className="text-2xl font-bold text-white">Download Manager</h2>
              <p className="text-gray-400 mt-1">
                {selectedFiles.size} of {files.length} files selected • {getTotalSize()}
              </p>
            </div>
            <button
              onClick={onClose}
              className="p-2 hover:bg-gray-800 rounded-lg transition-colors"
            >
              <X className="w-5 h-5 text-gray-400" />
            </button>
          </div>

          {/* Selection Controls */}
          <div className="flex items-center gap-4 mt-4">
            <button
              onClick={selectAll}
              className="text-sm text-blue-400 hover:text-blue-300"
            >
              Select All
            </button>
            <button
              onClick={deselectAll}
              className="text-sm text-blue-400 hover:text-blue-300"
            >
              Deselect All
            </button>
            <button
              onClick={() => setShowOptions(!showOptions)}
              className="ml-auto flex items-center gap-2 text-sm text-gray-400 hover:text-gray-300"
            >
              Options
              <ChevronDown className={`w-4 h-4 transition-transform ${showOptions ? 'rotate-180' : ''}`} />
            </button>
          </div>

          {/* Download Options */}
          {showOptions && (
            <div className="mt-4 p-4 bg-gray-800 rounded-lg space-y-3">
              <label className="flex items-center gap-2 text-sm text-gray-300">
                <input
                  type="checkbox"
                  checked={includeMetadata}
                  onChange={(e) => setIncludeMetadata(e.target.checked)}
                  className="rounded border-gray-600"
                />
                <FileJson className="w-4 h-4" />
                Include metadata JSON files
              </label>

              <div className="space-y-2">
                <label className="text-sm text-gray-300">Organization:</label>
                <select
                  value={organizationMethod}
                  onChange={(e) => setOrganizationMethod(e.target.value as any)}
                  className="w-full bg-gray-700 text-white rounded-lg px-3 py-2 text-sm"
                >
                  <option value="flat">Flat (no folders)</option>
                  <option value="date">By Date</option>
                  <option value="model">By Model</option>
                  <option value="type">By Type (images/videos)</option>
                </select>
              </div>
            </div>
          )}
        </div>

        {/* File List */}
        <div className="overflow-y-auto max-h-[400px] p-4">
          <div className="grid grid-cols-1 gap-2">
            {files.map((file) => (
              <div
                key={file.id}
                className={`flex items-center gap-3 p-3 rounded-lg cursor-pointer transition-colors ${
                  selectedFiles.has(file.id) ? 'bg-blue-900/30 border border-blue-500' : 'bg-gray-800 hover:bg-gray-700'
                }`}
                onClick={() => toggleFileSelection(file.id)}
              >
                <input
                  type="checkbox"
                  checked={selectedFiles.has(file.id)}
                  onChange={() => {}}
                  className="rounded border-gray-600"
                />

                {file.thumbnail && (
                  <img
                    src={file.thumbnail}
                    alt={file.name}
                    className="w-12 h-12 rounded object-cover"
                  />
                )}

                <div className="flex-1">
                  <p className="text-white font-medium text-sm">{file.name}</p>
                  <p className="text-gray-400 text-xs">
                    {file.type} • {formatFileSize(file.size)}
                    {file.model && ` • ${file.model}`}
                  </p>
                </div>

                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    downloadSingleFile(file);
                  }}
                  className="p-2 hover:bg-gray-600 rounded-lg transition-colors"
                  title="Download this file"
                >
                  <Download className="w-4 h-4 text-gray-400" />
                </button>
              </div>
            ))}
          </div>
        </div>

        {/* Footer */}
        <div className="border-t border-gray-800 p-6">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-4">
              {isDownloading && (
                <div className="flex items-center gap-2">
                  <Loader2 className="w-5 h-5 text-blue-400 animate-spin" />
                  <span className="text-gray-300">{downloadProgress}%</span>
                  <div className="w-32 h-2 bg-gray-700 rounded-full overflow-hidden">
                    <div
                      className="h-full bg-blue-500 transition-all duration-300"
                      style={{ width: `${downloadProgress}%` }}
                    />
                  </div>
                </div>
              )}
            </div>

            <div className="flex items-center gap-3">
              <button
                onClick={onClose}
                className="px-4 py-2 text-gray-300 hover:text-white transition-colors"
                disabled={isDownloading}
              >
                Cancel
              </button>
              {selectedFiles.size === 1 ? (
                <button
                  onClick={() => {
                    const file = files.find(f => selectedFiles.has(f.id));
                    if (file) downloadSingleFile(file);
                  }}
                  disabled={isDownloading}
                  className="px-6 py-2 bg-blue-600 hover:bg-blue-500 text-white rounded-lg font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
                >
                  <Download className="w-5 h-5" />
                  Download File
                </button>
              ) : (
                <button
                  onClick={downloadAsZip}
                  disabled={selectedFiles.size === 0 || isDownloading}
                  className="px-6 py-2 bg-blue-600 hover:bg-blue-500 text-white rounded-lg font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
                >
                  <Package className="w-5 h-5" />
                  Download as ZIP
                </button>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};