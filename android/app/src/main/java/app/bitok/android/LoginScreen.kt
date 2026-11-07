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

@Composable
fun LoginScreen(app: AppState) {
    val p = LocalPalette.current
    var phone by remember { mutableStateOf("") }
    var code by remember { mutableStateOf("") }
    var account by remember { mutableStateOf<DemoAccount?>(null) }
    var error by remember { mutableStateOf<String?>(null) }

    Screen("", null) {
        Column(Modifier.fillMaxWidth().padding(top = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Filled.SportsBaseball, null, tint = p.accent, modifier = Modifier.size(56.dp))
            Text("Биток", fontSize = 34.sp, fontWeight = FontWeight.SemiBold, color = p.text)
            Secondary("Каждая тренировка начинается с битка", size = 15)
        }
        GlassCard {
            if (account == null) {
                Title("Номер телефона")
                OutlinedTextField(phone, { phone = it }, Modifier.fillMaxWidth(), placeholder = { Text("+7 900 000-00-02") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone), singleLine = true)
                PrimaryButton("Получить код", enabled = phone.count { it.isDigit() } >= 10) {
                    val found = DemoAccount.find(phone)
                    if (found == null) error = "Такой учётки нет. Используйте тестовые номера ниже." else { account = found; error = null }
                }
            } else {
                Title("Код из SMS отправлен на ${account?.phone}")
                OutlinedTextField(code, { code = it }, Modifier.fillMaxWidth(), placeholder = { Text("Код") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword), singleLine = true)
                Secondary("Демо-режим: код для тестовых учёток — ${DemoAccount.OTP}")
                PrimaryButton("Войти", enabled = code.length >= 4) {
                    if (code == DemoAccount.OTP) account?.let { app.signIn(it) } else error = "Неверный код"
                }
                TextButton({ account = null; code = ""; error = null }, Modifier.fillMaxWidth()) { Text("Изменить номер") }
            }
            error?.let { Text(it, color = p.cancelled, fontSize = 14.sp) }
        }
        Title("Тестовые учётки")
        DemoAccount.entries.forEach { demo ->
            GlassCard(onClick = { app.signIn(demo) }) {
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
