#!/usr/bin/env python3
"""
SQLite FTS5 Indexer for Claude Knowledge Base
Uses only Python stdlib - no external dependencies
"""

import os
import sqlite3
import json
import hashlib
import argparse
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Tuple, Optional


class ClaudeIndexer:
    """Indexer for .claude knowledge base using SQLite FTS5"""
    
    # Categories mapped to directories
    CATEGORIES = {
        'metadata': 'Component analysis and system docs',
        'code_index': 'Code relationships and mappings',
        'debug_history': 'Debug sessions and fixes',
        'patterns': 'Implementation patterns',
        'qa': 'Questions and answers',
        'cheatsheets': 'Quick references',
        'delta': 'Change logs and updates',
        'anchors': 'Important code locations'
    }
    
    def __init__(self, claude_dir: str, db_path: str):
        self.claude_dir = Path(claude_dir)
        self.db_path = Path(db_path)
        self.conn = None
        self.cursor = None
        
    def connect(self):
        """Connect to SQLite database"""
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(str(self.db_path))
        self.cursor = self.conn.cursor()
        
    def disconnect(self):
        """Disconnect from database"""
        if self.conn:
            self.conn.close()
            
    def init_schema(self):
        """Initialize database schema with FTS5"""
        # Main documents table
        self.cursor.execute('''
            CREATE TABLE IF NOT EXISTS docs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                path TEXT UNIQUE NOT NULL,
                category TEXT NOT NULL,
                title TEXT,
                content TEXT NOT NULL,
                file_hash TEXT NOT NULL,
                indexed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                file_modified TIMESTAMP
            )
        ''')
        
        # FTS5 virtual table for full-text search
        self.cursor.execute('''
            CREATE VIRTUAL TABLE IF NOT EXISTS docs_fts USING fts5(
                title,
                content,
                category,
                content=docs,
                content_rowid=id
            )
        ''')
        
        # Triggers to keep FTS index in sync
        self.cursor.execute('''
            CREATE TRIGGER IF NOT EXISTS docs_ai AFTER INSERT ON docs BEGIN
                INSERT INTO docs_fts(rowid, title, content, category)
                VALUES (new.id, new.title, new.content, new.category);
            END
        ''')
        
        self.cursor.execute('''
            CREATE TRIGGER IF NOT EXISTS docs_ad AFTER DELETE ON docs BEGIN
                DELETE FROM docs_fts WHERE rowid = old.id;
            END
        ''')
        
        self.cursor.execute('''
            CREATE TRIGGER IF NOT EXISTS docs_au AFTER UPDATE ON docs BEGIN
                DELETE FROM docs_fts WHERE rowid = old.id;
                INSERT INTO docs_fts(rowid, title, content, category)
                VALUES (new.id, new.title, new.content, new.category);
            END
        ''')
        
        # Index for faster lookups
        self.cursor.execute('''
            CREATE INDEX IF NOT EXISTS idx_docs_path ON docs(path)
        ''')
        
        self.cursor.execute('''
            CREATE INDEX IF NOT EXISTS idx_docs_category ON docs(category)
        ''')
        
        self.conn.commit()
        
    def compute_file_hash(self, filepath: Path) -> str:
        """Compute SHA256 hash of file content"""
        sha256_hash = hashlib.sha256()
        with open(filepath, "rb") as f:
            for byte_block in iter(lambda: f.read(4096), b""):
                sha256_hash.update(byte_block)
        return sha256_hash.hexdigest()
        
    def extract_title(self, content: str, filepath: Path) -> str:
        """Extract title from markdown content or use filename"""
        lines = content.split('\n')
        for line in lines[:10]:  # Check first 10 lines
            if line.startswith('# '):
                return line[2:].strip()
        # Fallback to filename without extension
        return filepath.stem.replace('_', ' ').replace('-', ' ').title()
        
    def should_index_file(self, filepath: Path) -> bool:
        """Check if file should be indexed"""
        # Only index markdown and text files
        return filepath.suffix in ['.md', '.txt', '.markdown']
        
    def get_existing_file_hash(self, filepath: str) -> Optional[str]:
        """Get hash of existing indexed file"""
        self.cursor.execute(
            'SELECT file_hash FROM docs WHERE path = ?',
            (filepath,)
        )
        result = self.cursor.fetchone()
        return result[0] if result else None
        
    def index_file(self, filepath: Path, category: str, force: bool = False):
        """Index a single file"""
        if not self.should_index_file(filepath):
            return False
            
        rel_path = str(filepath.relative_to(self.claude_dir))
        file_hash = self.compute_file_hash(filepath)
        
        # Check if file needs updating
        existing_hash = self.get_existing_file_hash(rel_path)
        if existing_hash == file_hash and not force:
            return False  # File unchanged
            
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()
                
            title = self.extract_title(content, filepath)
            file_modified = datetime.fromtimestamp(filepath.stat().st_mtime)
            
            if existing_hash:
                # Update existing document
                self.cursor.execute('''
                    UPDATE docs 
                    SET content = ?, title = ?, file_hash = ?, 
                        indexed_at = CURRENT_TIMESTAMP, file_modified = ?
                    WHERE path = ?
                ''', (content, title, file_hash, file_modified, rel_path))
            else:
                # Insert new document
                self.cursor.execute('''
                    INSERT INTO docs (path, category, title, content, file_hash, file_modified)
                    VALUES (?, ?, ?, ?, ?, ?)
                ''', (rel_path, category, title, content, file_hash, file_modified))
                
            return True
            
        except Exception as e:
            print(f"Error indexing {filepath}: {e}")
            return False
            
    def index_category(self, category: str) -> Tuple[int, int]:
        """Index all files in a category directory"""
        category_dir = self.claude_dir / category
        if not category_dir.exists():
            return 0, 0
            
        indexed = 0
        updated = 0
        
        for filepath in category_dir.rglob('*'):
            if filepath.is_file():
                if self.index_file(filepath, category):
                    indexed += 1
                    
        return indexed, updated
        
    def clean_deleted_files(self):
        """Remove entries for files that no longer exist"""
        self.cursor.execute('SELECT id, path FROM docs')
        all_docs = self.cursor.fetchall()
        
        deleted = 0
        for doc_id, path in all_docs:
            full_path = self.claude_dir / path
            if not full_path.exists():
                self.cursor.execute('DELETE FROM docs WHERE id = ?', (doc_id,))
                deleted += 1
                
        return deleted
        
    def build_index(self, incremental: bool = True):
        """Build or update the search index"""
        self.connect()
        self.init_schema()
        
        total_indexed = 0
        total_updated = 0
        
        print(f"Indexing .claude directory: {self.claude_dir}")
        print("-" * 50)
        
        for category in self.CATEGORIES:
            indexed, updated = self.index_category(category)
            total_indexed += indexed
            total_updated += updated
            if indexed > 0:
                print(f"  {category:15} : {indexed} files indexed")
                
        # Clean up deleted files
        if incremental:
            deleted = self.clean_deleted_files()
            if deleted > 0:
                print(f"  Cleaned up {deleted} deleted files")
                
        self.conn.commit()
        
        # Get statistics
        self.cursor.execute('SELECT COUNT(*) FROM docs')
        total_docs = self.cursor.fetchone()[0]
        
        print("-" * 50)
        print(f"Total documents in index: {total_docs}")
        print(f"Files indexed/updated: {total_indexed}")
        
        # Optimize FTS index
        self.cursor.execute("INSERT INTO docs_fts(docs_fts) VALUES('optimize')")
        self.conn.commit()
        
        self.disconnect()


def main():
    parser = argparse.ArgumentParser(description='Index .claude knowledge base')
    parser.add_argument('--claude-dir', required=True, help='Path to .claude directory')
    parser.add_argument('--db-path', required=True, help='Path to SQLite database')
    parser.add_argument('--incremental', action='store_true', 
                       help='Incremental update (default)', default=True)
    parser.add_argument('--full', action='store_true', 
                       help='Full rebuild of index')
    
    args = parser.parse_args()
    
    incremental = not args.full
    
    indexer = ClaudeIndexer(args.claude_dir, args.db_path)
    indexer.build_index(incremental=incremental)


if __name__ == '__main__':
    main()