CREATE TABLE `access_limits` (
	`id` text PRIMARY KEY NOT NULL,
	`count` integer NOT NULL,
	`expires` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `water_locks` (
	`account` text PRIMARY KEY NOT NULL,
	`operation` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `water_operations` (
	`id` text PRIMARY KEY NOT NULL,
	`account` text NOT NULL,
	`machine` text NOT NULL,
	`state` text NOT NULL,
	`authorization` text,
	`authorization_frame` text NOT NULL,
	`consumption_frame` text,
	`receipt` text,
	`updated` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `access_sessions` (
	`id` text PRIMARY KEY NOT NULL,
	`account` text NOT NULL,
	`student` text NOT NULL,
	`school` text NOT NULL,
	`expires` integer NOT NULL,
	`binding` text
);
