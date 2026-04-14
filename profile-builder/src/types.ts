export interface RawProfile {
  schemaVersion: 1;
  collectedAt: string;
  ownerHints: {
    gitUserName?: string;
    gitUserEmail?: string;
    systemUser: string;
  };
  instructions: {
    claudeMd?: string;
    instructionsMd?: string;
    referenceFiles: string[];
  };
  settings: {
    hookKeys: string[];
  };
  tools: {
    skillNames: string[];
    pluginNames: string[];
  };
  memory: string[];
  sessionSamples: SessionSample[];
  auditSummary: ToolCount[];
  gitActivity: GitActivity[];
}

export interface SessionSample {
  file: string;
  mtime: string;
  firstUserMessage?: string;
  messageCount: number;
}

export interface ToolCount {
  tool: string;
  count: number;
}

export interface GitActivity {
  repo: string;
  commits: GitCommit[];
}

export interface GitCommit {
  sha: string;
  date: string;
  message: string;
}

export interface CachedProfile {
  schemaVersion: 1;
  createdAt: string;
  ttlDays: number;
  internal: RawProfile;
  draftYaml?: string;
  publicYaml: string;
}
