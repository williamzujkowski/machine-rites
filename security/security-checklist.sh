#!/bin/bash

# Security Checklist for Machine Rites
echo "🔒 Running Security Checklist..."

checks_passed=0
total_checks=5

# Check 1: No hardcoded secrets
echo "1. Checking for hardcoded secrets..."
if ! grep -r "password.*=" --exclude-dir=.git --exclude-dir=node_modules . >/dev/null 2>&1; then
    echo "   ✅ No hardcoded passwords found"
    ((checks_passed++))
else
    echo "   ❌ Potential hardcoded passwords found"
fi

# Check 2: Proper file permissions
echo "2. Checking file permissions..."
if [[ $(find . -name "*.sh" -perm 777 | wc -l) -eq 0 ]]; then
    echo "   ✅ No overly permissive scripts"
    ((checks_passed++))
else
    echo "   ⚠️ Some scripts have 777 permissions"
fi

# Check 3: No world-writable files
echo "3. Checking for world-writable files..."
if [[ $(find . -perm -002 -not -path "./node_modules/*" | wc -l) -eq 0 ]]; then
    echo "   ✅ No world-writable files"
    ((checks_passed++))
else
    echo "   ❌ World-writable files found"
fi

# Check 4: SSH key security
echo "4. Checking SSH key permissions..."
if [[ -d ~/.ssh ]]; then
    if [[ $(stat -c %a ~/.ssh) == "700" ]]; then
        echo "   ✅ SSH directory properly secured"
        ((checks_passed++))
    else
        echo "   ⚠️ SSH directory permissions could be tighter"
    fi
else
    echo "   ✅ No SSH directory to check"
    ((checks_passed++))
fi

# Check 5: Git hooks security
echo "5. Checking Git hooks..."
if [[ -d .git/hooks ]]; then
    hooks_secure=true
    for hook in .git/hooks/*; do
        if [[ -f "$hook" && -x "$hook" ]]; then
            if ! grep -q "#!/" "$hook"; then
                hooks_secure=false
                break
            fi
        fi
    done
    if $hooks_secure; then
        echo "   ✅ Git hooks appear secure"
        ((checks_passed++))
    else
        echo "   ⚠️ Git hooks need review"
    fi
else
    echo "   ✅ No Git hooks to check"
    ((checks_passed++))
fi

echo ""
echo "Security Check Results: $checks_passed/$total_checks passed"
if [[ $checks_passed -eq $total_checks ]]; then
    echo "🎉 All security checks passed!"
    exit 0
else
    echo "⚠️ Some security checks failed - review recommended"
    exit 1
fi
