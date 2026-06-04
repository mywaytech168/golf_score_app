START TRANSACTION;

CREATE TABLE `ball_trajectory_analyses` (
    `id` varchar(36) CHARACTER SET utf8mb4 NOT NULL,
    `user_id` varchar(36) CHARACTER SET utf8mb4 NOT NULL,
    `video_id` varchar(255) CHARACTER SET utf8mb4 NULL,
    `status` varchar(50) CHARACTER SET utf8mb4 NOT NULL DEFAULT 'pending',
    `clip_b2_path` varchar(512) CHARACTER SET utf8mb4 NULL,
    `hit_sec` double NULL,
    `flip_mode` int NOT NULL DEFAULT 0,
    `roi_cx_ratio` double NOT NULL,
    `roi_cy_ratio` double NOT NULL,
    `roi_radius` int NOT NULL DEFAULT 200,
    `track_pts_json` MEDIUMTEXT CHARACTER SET utf8mb4 NULL,
    `video_fps` double NULL,
    `video_width` int NULL,
    `video_height` int NULL,
    `video_rotation` int NULL,
    `error_message` varchar(1024) CHARACTER SET utf8mb4 NULL,
    `retry_count` int NOT NULL DEFAULT 0,
    `created_at` datetime NOT NULL,
    `completed_at` datetime NULL,
    CONSTRAINT `PK_ball_trajectory_analyses` PRIMARY KEY (`id`),
    CONSTRAINT `fk_btraj_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) CHARACTER SET=utf8mb4;

CREATE INDEX `idx_btraj_created_at` ON `ball_trajectory_analyses` (`created_at`);

CREATE INDEX `idx_btraj_status` ON `ball_trajectory_analyses` (`status`);

CREATE INDEX `idx_btraj_user_id` ON `ball_trajectory_analyses` (`user_id`);

CREATE INDEX `idx_btraj_video_id` ON `ball_trajectory_analyses` (`video_id`);

INSERT INTO `__EFMigrationsHistory` (`MigrationId`, `ProductVersion`)
VALUES ('20260601143029_AddBallTrajectoryAnalysis', '8.0.8');

COMMIT;

