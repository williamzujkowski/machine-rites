#!/bin/bash

echo "🪝 Completing Claude-Flow Hooks Setup"
echo "======================================"
echo ""

# Pre-Operation Hooks
echo "⚙️  Setting Pre-Operation Hooks..."

# Already done: pre-edit with auto-assign and load context
echo "  ✓ Pre-edit hook (already configured)"

echo "  → Pre-command hook (safety validation)"
npx claude-flow hooks pre-command --validate-safety true --prepare-resources true

echo "  → Pre-task hook"
npx claude-flow hooks pre-task

echo ""
echo "⚙️  Setting Post-Operation Hooks..."

echo "  → Post-edit hook (format, memory, neural training)"
npx claude-flow hooks post-edit --format true --update-memory true --train-neural true

echo "  → Post-command hook (metrics and results tracking)"
npx claude-flow hooks post-command --track-metrics true --store-results true

echo "  → Post-search hook (cache results)"
npx claude-flow hooks post-search

echo "  → Post-task hook"
npx claude-flow hooks post-task

echo ""
echo "⚙️  Setting MCP Integration Hooks..."

echo "  → MCP initialized hook"
npx claude-flow hooks mcp-initialized

echo "  → Agent spawned hook"
npx claude-flow hooks agent-spawned

echo "  → Task orchestrated hook"
npx claude-flow hooks task-orchestrated

echo "  → Neural trained hook"
npx claude-flow hooks neural-trained

echo ""
echo "⚙️  Setting Session Management Hooks..."

echo "  → Session-end hook (full features)"
npx claude-flow hooks session-end --generate-summary true --persist-state true --export-metrics true

echo "  → Session-restore hook"
npx claude-flow hooks session-restore

echo ""
echo "✅ All hooks configured successfully!"
echo ""
echo "📊 Testing Database Access..."
if command -v sqlite3 &> /dev/null; then
    echo "Hooks stored in database:"
    sqlite3 .swarm/memory.db "SELECT name, enabled FROM hooks LIMIT 5;" 2>/dev/null || echo "  (Table structure may vary)"
else
    echo "  Install sqlite3 to query the database: sudo apt install sqlite3"
fi

echo ""
echo "🚀 Next Steps:"
echo "  1. Test with a swarm: npx claude-flow hive init --topology mesh --agents 3"
echo "  2. Run a task: npx claude-flow orchestrate 'create a simple API' --parallel"
echo "  3. Check status: npx claude-flow hive status"
echo ""
echo "💡 Your hooks will now:"
echo "  • Validate commands before execution"
echo "  • Auto-format code after edits"
echo "  • Track metrics and performance"
echo "  • Train neural patterns from your usage"
echo "  • Save and restore session state"