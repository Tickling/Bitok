@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

// Демо-вход: телефон → код из SMS (для всех тестовых учёток — 1234) или быстрый вход кнопкой.
package app.bitok.android

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.SportsBaseball
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.input.OffsetMapping
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.ui.text.input.ImeAction

/** Маска телефона: храним 10 цифр, показываем «+7 900 000-00-01». */
object PhoneMask : VisualTransformation {
    private fun shown(digits: Int): Int = when {
        digits == 0 -> 0
        else -> 3 + digits + (if (digits > 3) 1 else 0) + (if (digits > 6) 1 else 0) + (if (digits > 8) 1 else 0)
    }
    override fun filter(text: AnnotatedString): TransformedText {
        val d = text.text
        val out = StringBuilder()
        if (d.isNotEmpty()) out.append("+7 ")
        d.forEachIndexed { i, c ->
            if (i == 3) out.append(' ')
            if (i == 6 || i == 8) out.append('-')
            out.append(c)
        }
        val mapping = object : OffsetMapping {
            override fun originalToTransformed(offset: Int) = shown(offset).coerceAtMost(out.length).let { if (offset == 0 && d.isNotEmpty()) 3 else it }
            override fun transformedToOriginal(offset: Int): Int {
                for (k in 0..d.length) if (shown(k) >= offset) return k
                return d.length
            }
        }
        return TransformedText(AnnotatedString(out.toString()), mapping)
    }

    /** Из любого ввода — 10 цифр без ведущей 7/8. */
    fun digits(input: String): String {
        var d = input.filter { it.isDigit() }
        if (d.length == 11 && (d.first() == '7' || d.first() == '8')) d = d.drop(1)
        return d.take(10)
    }
}

@Composable
fun LoginScreen(app: AppState) {
    val p = LocalPalette.current
    var phone by remember { mutableStateOf("") }
    var code by remember { mutableStateOf("") }
    var account by remember { mutableStateOf<DemoAccount?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    val keyboard = LocalSoftwareKeyboardController.current
    val focus = LocalFocusManager.current
    fun enter(demo: DemoAccount) { focus.clearFocus(); keyboard?.hide(); app.signIn(demo) }
    fun requestCode() {
        val found = DemoAccount.find("+7$phone")
        if (found == null) error = "Такой учётки нет. Используйте тестовые номера ниже." else { account = found; error = null }
    }
    fun verify() {
        if (code == DemoAccount.OTP) account?.let { enter(it) } else error = "Неверный код"
    }

    Screen("", null) {
        Column(Modifier.fillMaxWidth().padding(top = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Filled.SportsBaseball, null, tint = p.accent, modifier = Modifier.size(56.dp))
            Text("Биток", fontSize = 34.sp, fontWeight = FontWeight.SemiBold, color = p.text)
            Secondary("Каждая тренировка начинается с битка", size = 15)
        }
        GlassCard {
            if (account == null) {
                Title("Номер телефона")
                OutlinedTextField(phone, { input ->
                        // Первая 7 или 8 — это код страны, он уже в маске
                        phone = if (phone.isEmpty() && input.length == 1 && (input == "7" || input == "8")) "" else PhoneMask.digits(input)
                    }, Modifier.fillMaxWidth(), placeholder = { Text("+7 900 000-00-02") },
                    visualTransformation = PhoneMask,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone, imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { if (phone.length == 10) requestCode() else keyboard?.hide() }), singleLine = true)
                PrimaryButton("Получить код", enabled = phone.length == 10) { requestCode() }
            } else {
                Title("Код из SMS отправлен на ${account?.phone}")
                OutlinedTextField(code, { input ->
                        code = input.filter { it.isDigit() }.take(4)
                        if (code.length == 4) verify()
                    }, Modifier.fillMaxWidth(), placeholder = { Text("Код") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword, imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { verify() }), singleLine = true)
                Secondary("Демо-режим: код для тестовых учёток — ${DemoAccount.OTP}")
                PrimaryButton("Войти", enabled = code.length >= 4) { verify() }
                TextButton({ account = null; code = ""; error = null }, Modifier.fillMaxWidth()) { Text("Изменить номер") }
            }
            error?.let { Text(it, color = p.cancelled, fontSize = 14.sp) }
        }
        Title("Тестовые учётки")
        DemoAccount.entries.forEach { demo ->
            GlassCard(onClick = { enter(demo) }) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Column(Modifier.weight(1f)) {
                        Text("${demo.roleTitle}: ${demo.displayName}", fontWeight = FontWeight.SemiBold, color = p.text)
                        Secondary("${demo.phone} · код ${DemoAccount.OTP}")
                    }
                    Icon(Icons.AutoMirrored.Filled.ArrowForward, null, tint = p.accent)
                }
            }
        }
        Spacer(Modifier.padding(8.dp))
    }
}
