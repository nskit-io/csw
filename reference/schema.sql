-- CSW (Claude Subscription Worker) Reference Schema
-- MySQL 8.0+ required
-- This is a clean reference schema. Adapt as needed for your deployment.

CREATE DATABASE IF NOT EXISTS csw
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE csw;

-- ============================================================
-- Sessions: Conversation containers
-- ============================================================
CREATE TABLE IF NOT EXISTS sessions (
  id VARCHAR(36) NOT NULL PRIMARY KEY,
  name VARCHAR(255) DEFAULT NULL,
  summary TEXT DEFAULT NULL,
  status ENUM('active','archived') NOT NULL DEFAULT 'active',
  message_count INT NOT NULL DEFAULT 0,
  system_prompt TEXT DEFAULT NULL,
  model VARCHAR(100) DEFAULT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  INDEX idx_sessions_status (status),
  INDEX idx_sessions_updated (updated_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- Messages: Individual messages within sessions
-- ============================================================
CREATE TABLE IF NOT EXISTS messages (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  session_id VARCHAR(36) NOT NULL,
  role ENUM('user','assistant','system') NOT NULL,
  content MEDIUMTEXT NOT NULL,
  output_format JSON DEFAULT NULL,
  is_compacted TINYINT(1) NOT NULL DEFAULT 0,
  job_id VARCHAR(36) DEFAULT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  INDEX idx_messages_session (session_id, is_compacted, created_at),
  INDEX idx_messages_job (job_id),
  CONSTRAINT fk_messages_session FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- Memory: Per-session key-value context store
-- Categories: rule (instructions), property (facts), action (behaviors)
-- ============================================================
CREATE TABLE IF NOT EXISTS memory (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  session_id VARCHAR(36) NOT NULL,
  category ENUM('rule','property','action') NOT NULL,
  key_name VARCHAR(255) NOT NULL,
  value TEXT NOT NULL,
  priority INT NOT NULL DEFAULT 0,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  UNIQUE KEY uk_memory_session_cat_key (session_id, category, key_name),
  INDEX idx_memory_session_active (session_id, is_active, priority DESC),
  CONSTRAINT fk_memory_session FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- Jobs: Request tracking and audit log
-- ============================================================
CREATE TABLE IF NOT EXISTS jobs (
  id VARCHAR(36) NOT NULL PRIMARY KEY,
  session_id VARCHAR(36) DEFAULT NULL,
  status ENUM('queued','processing','completed','failed','timeout') NOT NULL DEFAULT 'queued',
  request_body JSON DEFAULT NULL,
  response_body JSON DEFAULT NULL,
  claude_raw MEDIUMTEXT DEFAULT NULL,
  error_message TEXT DEFAULT NULL,
  duration_ms INT DEFAULT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  completed_at DATETIME(3) DEFAULT NULL,
  INDEX idx_jobs_status (status),
  INDEX idx_jobs_session (session_id),
  INDEX idx_jobs_created (created_at),
  CONSTRAINT fk_jobs_session FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- Presets: Reusable prompt templates
-- ============================================================
CREATE TABLE IF NOT EXISTS presets (
  id VARCHAR(36) NOT NULL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  description TEXT DEFAULT NULL,
  command VARCHAR(255) DEFAULT NULL,
  system_prompt TEXT DEFAULT NULL,
  output_format JSON DEFAULT NULL,
  sample_input TEXT DEFAULT NULL,
  sample_memory JSON DEFAULT NULL,
  options JSON DEFAULT NULL,
  tags VARCHAR(500) DEFAULT NULL,
  cache_pool_target INT DEFAULT NULL,
  usage_count INT NOT NULL DEFAULT 0,
  last_used_at DATETIME(3) DEFAULT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  INDEX idx_presets_name (name),
  INDEX idx_presets_tags (tags),
  INDEX idx_presets_usage (usage_count DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- Response Cache: Metadata + simple mode responses
-- ============================================================
CREATE TABLE IF NOT EXISTS response_cache (
  cache_key VARCHAR(500) NOT NULL PRIMARY KEY,
  response MEDIUMTEXT NOT NULL,
  hit_count INT NOT NULL DEFAULT 0,
  pool_target INT DEFAULT NULL,
  pool_size INT NOT NULL DEFAULT 0,
  is_growing TINYINT(1) NOT NULL DEFAULT 0,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  expires_at DATETIME(3) DEFAULT NULL,
  INDEX idx_cache_expires (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- Response Cache Pool: Individual pool entries for diverse responses
-- ============================================================
CREATE TABLE IF NOT EXISTS response_cache_pool (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  cache_key VARCHAR(500) NOT NULL,
  response MEDIUMTEXT NOT NULL,
  hit_count INT NOT NULL DEFAULT 0,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  INDEX idx_pool_key (cache_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
